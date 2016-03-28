//
//  Session.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import XCGLogger
#if os(OSX)
	import AppKit
#endif
import SwiftyJSON
import MessagePackSwift

public enum ExecuteType: String {
	case Run = "run", Source = "source", None = ""
}

public class Session : NSObject, SessionFileHandlerDelegate {
	///tried kvo, forced to use notifications
	class Manager: NSObject {
		dynamic var currentSession: Session? {
			didSet { NSNotificationCenter.defaultCenter().postNotificationNameOnMainThread(CurrentSessionChangedNotification, object: currentSession!) }
		}
	}
	static var manager: Manager = Manager()
	
	let workspace : Workspace
	let wsSource : WebSocketSource
	let appStatus: AppStatus
	let fileHandler: SessionFileHandler
	weak var delegate : SessionDelegate?
	var variablesVisible : Bool = false {
		didSet {
			if variablesVisible && variablesVisible != oldValue {
				sendMessage(["cmd":"watchVariables", "watch":variablesVisible])
			}
		}
	}
	var helpRegex : NSRegularExpression = {
		return try! NSRegularExpression(pattern: "(help\\(\\\"?([\\w\\d]+)\\\"?\\))\\s*;?\\s?", options: [.DotMatchesLineSeparators])
	}()
	
	private(set) var connectionOpen:Bool = false
	private var keepAliveTimer:dispatch_source_t = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue())
	private var waitingOnTransactions: [String:(String) -> Void] = [:]
	
	init(_ wspace:Workspace,  source:WebSocketSource, appStatus:AppStatus, networkConfig config:NSURLSessionConfiguration, delegate:SessionDelegate?=nil)
	{
		workspace = wspace
		self.delegate = delegate
		self.wsSource = source
		self.appStatus = appStatus
		self.fileHandler = DefaultSessionFileHandler(wspace: workspace, baseUrl: RestServer.sharedInstance.baseUrl!, config: config, appStatus: appStatus)

		super.init()
		fileHandler.fileDelegate = self
		wsSource.binaryType = .NSData
		wsSource.event.open = {
			dispatch_async(dispatch_get_main_queue()) { [unowned self] in
				self.connectionOpen = true
				Session.manager.currentSession = self
				self.fileHandler.loadFiles()
				self.delegate?.sessionOpened()
			}
		}
		wsSource.event.close = { [unowned self] (code, reason, clear)in
			self.connectionOpen = false
			self.delegate?.sessionClosed()
		}
		wsSource.event.message = { [unowned self] message in
			self.handleReceivedMessage(message)
		}
		wsSource.event.error = { [unowned self] error in
			self.delegate?.sessionErrorReceived(error)
		}
		//setup a timer to send keep alive messages every 2 minutes
		let interval = 120 * NSEC_PER_SEC
		dispatch_source_set_timer(keepAliveTimer, dispatch_time(DISPATCH_TIME_NOW, Int64(interval)), interval, NSEC_PER_SEC/10)
		dispatch_source_set_event_handler(keepAliveTimer) {
			self.sendMessage(["msg":"keepAlive"])
		}
		dispatch_resume(keepAliveTimer)
	}
	
	func open(request:NSURLRequest) {
		self.wsSource.open(request: request, subProtocols: [])
	}
	
	func close() {
		self.wsSource.close(1000, reason: "") //default values that can't be specified in a protocol
	}
	
	//MARK: public request methods
	func executeScript(srcScript: String, type:ExecuteType = .Run) {
		//don't send empty scripts
		guard srcScript.characters.count > 0 else {
			return
		}
		var script = srcScript
		let helpCheck = helpRegex.firstMatchInString(script, options: [], range: NSMakeRange(0, script.utf16.count))
		if helpCheck?.numberOfRanges == 3 {
			let topic = script.substringWithRange((helpCheck?.rangeAtIndex(2).toStringRange(script))!)
			let adjScript = script.stringByReplacingCharactersInRange((helpCheck?.range.toStringRange(script))!, withString: "")
			lookupInHelp(topic)
			guard adjScript.utf16.count > 0 else {
				return
			}
			script = adjScript
		}
		sendMessage(["msg":"execute", "type":type.rawValue, "code":script])
	}
	
	func executeScriptFile(fileId:Int, type:ExecuteType = .Run) {
		sendMessage(["msg":"execute", "type":type.rawValue, "fileId":fileId])
	}
	
	func clearVariables() {
		executeScript("rc2.clearEnvironment()");
	}
	
	func lookupInHelp(str:String) {
		sendMessage(["msg":"help", "topic":str])
	}
	
	func requestUserList() {
		sendMessage(["msg":"userList"])
	}
	
	func forceVariableRefresh() {
		sendMessage(["msg":"watchVariables", "watch":true])
	}
	
	//MARK: SessionFileHandlerDelegate methods
	func filesLoaded() {
		appStatus.updateStatus(nil)
		delegate?.sessionFilesLoaded(self)
	}
	
	///sends document changes to the server
	///parameter completionHandler: called when the server confirms it saved it and passed to any subsytems (like R)
	func sendSaveFileMessage(document:EditorDocument, executeType:ExecuteType = .None, completionHandler:(EditorDocument, NSError?) -> Void) {
		let data = NSMutableData()
		let transId = encodeDocumentSaveMessage(document, data: data)
		waitingOnTransactions[transId] = { (responseId) in
			completionHandler(document, nil)
		}
		self.wsSource.send(data)
	}
	
	//MARK: other public methods
//	func noHelpFoundString(topic:String) -> NSAttributedString {
//		return NSAttributedString(string: "No help available for '\(topic)'\n", attributes: attrDictForColor(.Help))
//	}
//	
	//MARK: private methods
	
	//assumes currentContents of document is what should be sent to the server
	///returns a token to uniquely identify this transaction, encoded into the message data
	private func encodeDocumentSaveMessage(document:EditorDocument, data:NSMutableData) -> String {
		let uniqueIdent = NSUUID().UUIDString
		let encoder = MessagePackEncoder()
		var attrs = ["msg":MessageValue.forValue("save"), "apiVersion":MessageValue.forValue(Int(1))]
		attrs["transId"] = MessageValue.forValue(uniqueIdent)
		attrs["fileId"] = MessageValue.forValue(document.file.fileId)
		attrs["fileVersion"] = MessageValue.forValue(document.file.version)
		attrs["content"] = MessageValue.forValue(document.currentContents)
		encoder.encodeValue(MessageValue.DictionaryValue(MessageValueDictionary(attrs)))
		data.appendData(encoder.data!)
	data.writeToURL(NSURL(fileURLWithPath: "/tmp/lastSaveToServer"), atomically: true)
		return uniqueIdent
	}
	
	private func processBinaryResponse(data:NSData) {
		var parsedValues:[MessageValue]? = nil
		let decoder = MessagePackDecoder(data: data)
		do {
			parsedValues = try decoder.parse()
		} catch let err {
			log.error("error parsing binary message:\(err)")
		}
		//get the dictionary of messagevalues
		guard case MessageValue.DictionaryValue(let msgDict) = parsedValues![0] else {
			log.warning("received invalid binary response from server")
			return
		}
		let dict = msgDict.nativeValue()
		//eventually we need to switch on the msg property. For now, just verify it is the only one we support
		guard let msgStr = dict["msg"] as? String where msgStr == "saveResponse" else {
			log.warning("received unknown binary message")
			return
		}
		handleSaveResponse(dict)
	}
	
	//we've got a dictionary of the save response. keys should be transId, success, file, error
	private func handleSaveResponse(rawDict:[String:AnyObject]) {
		if let transId = rawDict["transId"] as? String {
			waitingOnTransactions[transId]?(transId)
			waitingOnTransactions.removeValueForKey(transId)
		}
		if let errorDict = rawDict["error"] as? Dictionary<String,AnyObject> {
			//TODO: inform user
			log.error("got save response error \(errorDict["message"] as? String)")
			return
		}
		do {
			let fileData = try NSJSONSerialization.dataWithJSONObject(rawDict["file"]!, options: [])
			let json = JSON(data: fileData)
			let file = File(json: json)
			let idx = workspace.indexOfFilePassingTest()
			{ obj, idx, _ in
				return (obj as! File).fileId == file.fileId
			}
			assert(idx != NSNotFound)
			workspace.replaceFileAtIndex(idx, withFile: file)
		} catch let err {
			log.error("error parsing binary message: \(err)")
		}
	}
	
	private func handleReceivedMessage(message:Any) {
		if let stringMessage = message as? String {
			let jsonMessage = JSON.parse(stringMessage)
			if let response = ServerResponse.parseResponse(jsonMessage) {
				self.delegate?.sessionMessageReceived(response)
			}
		} else if let _ = message as? NSData {
			processBinaryResponse(message as! NSData)
		} else {
			log.error("invalid binary data format received: \(message)")
		}
	}
	
	func sendMessage(message:Dictionary<String,AnyObject>) -> Bool {
		guard NSJSONSerialization.isValidJSONObject(message) else {
			return false
		}
		do {
			let json = try NSJSONSerialization.dataWithJSONObject(message, options: [])
			let jsonStr = NSString(data: json, encoding: NSUTF8StringEncoding)
			self.wsSource.send(jsonStr as! String)
		} catch let err as NSError {
			log.error("error sending json message on websocket:\(err)")
			return false
		}
		return true
	}
}
