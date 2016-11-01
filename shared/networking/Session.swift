//
//  Session.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
#if os(OSX)
	import AppKit
#endif
import SwiftyJSON
import MessagePackSwift
import BrightFutures
import os

public enum ExecuteType: String {
	case Run = "run", Source = "source", None = ""
}

public enum FileOperation: String {
	case Remove = "rm", Rename = "rename", Duplicate = "duplicate"
}

open class Session : NSObject, SessionFileHandlerDelegate {
	//MARK: properties
	
	//the workspace this session represents
	let workspace : Workspace
	///the WebSocket for communicating with the server
	let wsSource : WebSocketSource
	///used to report progress on async operations
	weak var appStatus: AppStatus?
	///abstraction of file handling
	let fileHandler: SessionFileHandler
	///a unique per-host identifier
	let hostIdentifier: String
	///
	weak var delegate : SessionDelegate?
	weak var restServer: RestServer?
	fileprivate var openPromise: Promise<Session, NSError>?

	///regex used to catch user entered calls to help so we can hijack and display through our mechanism
	var helpRegex : NSRegularExpression = {
		return try! NSRegularExpression(pattern: "(help\\(\\\"?([\\w\\d]+)\\\"?\\))\\s*;?\\s?", options: [.dotMatchesLineSeparators])
	}()
	
	fileprivate(set) var connectionOpen:Bool = false
	fileprivate var keepAliveTimer:DispatchSource = DispatchSource.makeTimerSource(flags: DispatchSource.TimerFlags(rawValue: UInt(0)), queue: DispatchQueue.main) /*Migrator FIXME: Use DispatchSourceTimer to avoid the cast*/ as! DispatchSource
	
	///closure syntax for a transaction complete callback
	/// - parameter $0: the transaction id (key in the pendingTransaction dictionary)
	/// - parameter $1: the message received from the server, if available
	typealias TransactionCompletion = (String, JSON?) -> Void
	
	///a dictionary of transaction ids mapped to closures called when the server says the transaction is complete
	fileprivate var pendingTransactions: [String:TransactionCompletion] = [:]
	///if we are getting variable updates from the server
	fileprivate var watchingVariables:Bool = false
	
	
	//MARK: init/open/close
	init(_ wspace:Workspace, source:WebSocketSource, restServer rserver:RestServer, networkConfig config:URLSessionConfiguration, hostIdentifier:String, delegate:SessionDelegate?=nil)
	{
		workspace = wspace
		self.delegate = delegate
		self.wsSource = source
		self.hostIdentifier = hostIdentifier
		self.restServer = rserver
		self.fileHandler = DefaultSessionFileHandler(wspace: workspace, baseUrl: restServer!.baseUrl!, config: config, appStatus: appStatus)

		super.init()
		fileHandler.fileDelegate = self
		wsSource.binaryType = .nsData
		wsSource.event.open = { [unowned self] in
			DispatchQueue.main.async {
				self.connectionOpen = true
				self.fileHandler.loadFiles()
				assert(self.openPromise != nil)
				self.openPromise?.success(self)
				self.openPromise = nil
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
			if self.openPromise != nil {
				self.openPromise!.failure(error as NSError)
				self.openPromise = nil
			} else {
				self.delegate?.sessionErrorReceived(error)
			}
		}
		//setup a timer to send keep alive messages every 2 minutes
		let start = DispatchTime.now() + DispatchTimeInterval.seconds(120)
		keepAliveTimer.scheduleRepeating(deadline: start, interval: .seconds(120), leeway: .milliseconds(100))
		keepAliveTimer.setEventHandler { [unowned self] in
			_ = self.sendMessage(["msg":"keepAlive" as AnyObject])
		}
		keepAliveTimer.resume()
	}
	
	deinit {
		os_log("session dealloc", type:.info)
	}
	
	///opens the websocket with the specified request
	/// - parameter request: a ws:// or wss:// request to use for the websocket
	/// - returns: future for the open session (with file loading started) or an error
	func open(_ request:URLRequest) -> Future<Session, NSError> {
		assert(openPromise == nil)
		let promise = Promise<Session, NSError>()
		openPromise = promise
		wsSource.open(request: request, subProtocols: [])
		return promise.future
	}
	
	///closes the websocket, which can not be reopened
	func close() {
		keepAliveTimer.cancel()
		self.wsSource.close(1000, reason: "") //default values that can't be specified in a protocol
	}
	
	//MARK: public request methods
	
	///Sends an execute request to the server
	/// - parameter srcScript: the script code to send to the server
	/// - parameter type: whether to run or source the script
	func executeScript(_ srcScript: String, type:ExecuteType = .Run) {
		//don't send empty scripts
		guard srcScript.characters.count > 0 else {
			return
		}
		var script = srcScript
		let helpCheck = helpRegex.firstMatch(in: script, options: [], range: NSMakeRange(0, script.utf16.count))
		if helpCheck?.numberOfRanges == 3 {
			let topic = script.substring(with: (helpCheck?.rangeAt(2).toStringRange(script))!)
			let adjScript = script.replacingCharacters(in: (helpCheck?.range.toStringRange(script))!, with: "")
			delegate?.respondToHelp(topic)
			guard adjScript.utf16.count > 0 else {
				return
			}
			script = adjScript
		}
		sendMessage(["msg":"execute" as AnyObject, "type":type.rawValue as AnyObject, "code":script as AnyObject])
	}
	
	/// sends a request to execute a script file
	/// - parameter fileId: the id of the file to execute
	/// - parameter type: whether to run or source the file
	func executeScriptFile(_ fileId:Int, type:ExecuteType = .Run) {
		sendMessage(["msg":"execute" as AnyObject, "type":type.rawValue as AnyObject, "fileId":fileId as AnyObject])
	}
	
	/// clears all variables in the global environment
	func clearVariables() {
		executeScript("rc2.clearEnvironment()");
	}
	
	/// asks the server for a refresh of all environment variables
	func forceVariableRefresh() {
		sendMessage(["msg":"watchVariables" as AnyObject, "watch":true as AnyObject])
	}
	
	/// ask the server to send a message with current variable values and delta messages as they change
	func startWatchingVariables() {
		if (watchingVariables) { return; }
		sendMessage(["msg":"watchVariables" as AnyObject, "watch":true as AnyObject])
		watchingVariables = true
	}

	/// ask the server to stop sending environment delta messages
	func stopWatchingVariables() {
		if (!watchingVariables) { return }
		sendMessage(["msg":"watchVariables" as AnyObject, "watch":false as AnyObject])
		watchingVariables = false
	}
	
	/// asks the server to remove a file
	/// - parameter file: The file to remove
	func removeFile(_ file:File) {
		let transId = UUID().uuidString
		sendMessage(["msg":"fileop" as AnyObject, "fileId":file.fileId as AnyObject, "fileVersion":file.version as AnyObject, "operation":"rm" as AnyObject, "transId":transId as AnyObject])
		let prog = Progress(parent: nil, userInfo: nil)
		prog.localizedDescription = "Removing file '\(file.name)'"
		appStatus?.currentProgress = prog
		pendingTransactions[transId] = { [weak self] (responseId, _) in
			self?.appStatus?.currentProgress = nil
		}
	}
}

//MARK: SessionFileHandlerDelegate methods
extension Session {
	
	/// callback when the file handler has loaded all files
	func filesLoaded() {
		appStatus?.currentProgress = nil
		delegate?.sessionFilesLoaded(self)
	}
	
	///sends document changes to the server
	///parameter completionHandler: called when the server confirms it saved it and passed to any subsytems (like R)
	func sendSaveFileMessage(_ document:EditorDocument, executeType:ExecuteType = .None, completionHandler:@escaping (EditorDocument, NSError?) -> Void) {
		let data = NSMutableData()
		let transId = encodeDocumentSaveMessage(document, data: data)
		pendingTransactions[transId] = { (responseId, _) in
			completionHandler(document, nil)
		}
		self.wsSource.send(data)
	}
}

//MARK: private methods
private extension Session {
	//assumes currentContents of document is what should be sent to the server
	///returns a token to uniquely identify this transaction, encoded into the message data
	func encodeDocumentSaveMessage(_ document:EditorDocument, data:NSMutableData) -> String {
		let uniqueIdent = UUID().uuidString
		let encoder = MessagePackEncoder()
		var attrs = ["msg":MessageValue.forValue("save"), "apiVersion":MessageValue.forValue(Int(1))]
		attrs["transId"] = MessageValue.forValue(uniqueIdent)
		attrs["fileId"] = MessageValue.forValue(document.file.fileId)
		attrs["fileVersion"] = MessageValue.forValue(document.file.version)
		attrs["content"] = MessageValue.forValue(document.savedContents!)
		encoder.encodeValue(MessageValue.DictionaryValue(MessageValueDictionary(attrs)))
		data.append(encoder.data!)
		data.write(to: URL(fileURLWithPath: "/tmp/lastSaveToServer"), atomically: true)
		return uniqueIdent
	}
	
	///processes a binary response from the WebSocket
	/// - parameter data: The MessagePack data
	func processBinaryResponse(_ data:Data) {
		var parsedValues:[MessageValue]? = nil
		let decoder = MessagePackDecoder(data: data)
		do {
			parsedValues = try decoder.parse()
		} catch let err {
			os_log("error parsing binary message:%{public}@", type:.error, err as NSError)
		}
		//get the dictionary of messagevalues
		guard case MessageValue.DictionaryValue(let msgDict) = parsedValues![0] else {
			os_log("received invalid binary response from server")
			return
		}
		let dict = msgDict.nativeValue()
		switch dict["msg"] as! String {
		case "saveResponse":
			handleSaveResponse(dict as [String : AnyObject])
		case "showOutput":
			let file = File(dict: dict["file"] as! [String:AnyObject])
			let response = ServerResponse.showOutput(queryId: dict["queryId"] as! Int, updatedFile: file)
			delegate?.sessionMessageReceived(response)
			_ = fileHandler.updateFile(file, withData: dict["fileData"] as? Data)
		default:
			os_log("received unknown binary message: %{public}@", dict["msg"] as! String)
			return
		}
	}
	
	//we've got a dictionary of the save response. keys should be transId, success, file, error
	func handleSaveResponse(_ rawDict:[String:AnyObject]) {
		if let transId = rawDict["transId"] as? String {
			pendingTransactions[transId]?(transId, nil)
			pendingTransactions.removeValue(forKey: transId)
		}
		if let errorDict = rawDict["error"] as? Dictionary<String,AnyObject> {
			//TODO: inform user
			os_log("got save response error: %{public}@", type:.error, (errorDict["message"] as? String)!)
			return
		}
		do {
			let fileData = try JSONSerialization.data(withJSONObject: rawDict["file"]!, options: [])
			let json = JSON(data: fileData)
			let file = File(json: json)
			guard let idx = workspace.indexOfFilePassingTest({ $0.fileId == file.fileId }) else {
				os_log("saveResponse for file not in workspace: %{public}@", type:.error, file.name)
				return
			}
			workspace.replaceFile(at:idx, withFile: file)
		} catch let err as NSError {
			os_log("error parsing binary message: %{public}@", type:.error, err)
		}
	}
	
	func handleFileResponse(_ transId:String, operation:FileOperation, file:File) {
		switch(operation) {
		case .Duplicate:
			//TODO: support
			break
		case .Rename:
			//TODO: support
			break
		case .Remove:
			if let idx = workspace.indexOfFile(file) {
				workspace.removeFile(at:idx)
			} else {
				os_log("got remove response for unknown file")
			}
			break
		}
	}
	
	func handleReceivedMessage(_ message:Any) {
		if let stringMessage = message as? String {
			let jsonMessage = JSON.parse(stringMessage)
			os_log("got message %{public}s", jsonMessage["msg"].stringValue)
			if let response = ServerResponse.parseResponse(jsonMessage) {
				if case let .fileOperationResponse(transId, operation, file) = response {
					handleFileResponse(transId, operation:operation, file:file)
				} else {
					self.delegate?.sessionMessageReceived(response)
				}
			}
			if let transId = jsonMessage["transId"].string {
				pendingTransactions[transId]?(transId, jsonMessage)
				pendingTransactions.removeValue(forKey: transId)
			}
		} else if let _ = message as? Data {
			processBinaryResponse(message as! Data)
		} else {
			os_log("invalid binary data format received: %{public}@", type:.error)
		}
	}
	
	@discardableResult func sendMessage(_ message:Dictionary<String,AnyObject>) -> Bool {
		guard JSONSerialization.isValidJSONObject(message) else {
			return false
		}
		do {
			let json = try JSONSerialization.data(withJSONObject: message, options: [])
			let jsonStr = NSString(data: json, encoding: String.Encoding.utf8.rawValue)
			self.wsSource.send(jsonStr as! String)
		} catch let err as NSError {
			os_log("error sending json message on websocket: %{public}@", type:.error, err)
			return false
		}
		return true
	}
}
