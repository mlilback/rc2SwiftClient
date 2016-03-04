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
	private var loadTimer:dispatch_source_t = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue())
	
	init(_ wspace:Workspace,  source:WebSocketSource, appStatus:AppStatus, networkConfig config:NSURLSessionConfiguration, delegate:SessionDelegate?=nil)
	{
		workspace = wspace
		self.delegate = delegate
		self.wsSource = source
		self.appStatus = appStatus
		self.fileHandler = DefaultSessionFileHandler(wspace: workspace, baseUrl: RestServer.sharedInstance.baseUrl!, config: config, appStatus: appStatus)

		super.init()
		fileHandler.fileDelegate = self
		wsSource.event.open = {
			dispatch_async(dispatch_get_main_queue()) {
				self.connectionOpen = true
				Session.manager.currentSession = self
				self.fileHandler.loadFiles()
				self.delegate?.sessionOpened()
			}
		}
		wsSource.event.close = { (code, reason, clear) in
			self.connectionOpen = false
			self.delegate?.sessionClosed()
		}
		wsSource.event.message = { message in
//			log.info("got message: \(message as? String)")
			let jsonMessage = JSON.parse(message as! String)
			if let response = ServerResponse.parseResponse(jsonMessage) {
				self.delegate?.sessionMessageReceived(response)
			}
		}
		wsSource.event.error = { error in
			self.delegate?.sessionErrorReceived(error)
		}
	}
	
	func open(request:NSURLRequest) {
		self.wsSource.open(request: request, subProtocols: [])
	}
	
	func close() {
		self.wsSource.close(1000, reason: "") //default values that can't be specified in a protocol
	}
	
	func loadFiles() {
//		let progress = NSProgress(totalUnitCount: 10)
//		progress.rc2_addCompletionHandler() {
//			dispatch_source_cancel(self.loadTimer)
//			self.appStatus.updateStatus(nil)
//			self.fileHandler.loadFiles()
//		}
//		progress.localizedDescription = NSLocalizedString("Loading files…", comment: "")
//		appStatus.updateStatus(progress)
//		dispatch_source_set_timer(loadTimer, dispatch_time(DISPATCH_TIME_NOW, Int64(NSEC_PER_SEC)), NSEC_PER_SEC, 200)
//		dispatch_source_set_event_handler(loadTimer) {
//			progress.completedUnitCount = progress.completedUnitCount + 1
//		}
//		dispatch_resume(loadTimer)
	}
	
	//MARK: public request methods
	func executeScript(var script: String) {
		//don't send empty scripts
		guard script.characters.count > 0 else {
			return
		}
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
		sendMessage(["msg":"execute", "code":script])
	}
	
	func executeScriptFile(fileId:Int) {
		sendMessage(["msg":"execute", "fileId":fileId])
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
	
	//MARK: other public methods
//	func noHelpFoundString(topic:String) -> NSAttributedString {
//		return NSAttributedString(string: "No help available for '\(topic)'\n", attributes: attrDictForColor(.Help))
//	}
//	
	//MARK: private methods
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

