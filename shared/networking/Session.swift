//
//  Rc2Session.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import XCGLogger
#if os(OSX)
	import AppKit
#endif

protocol SessionDelegate : class {
	func sessionOpened()
	func sessionClosed()
	func sessionMessageReceived(msg:JSON)
	func sessionErrorReceived(error:ErrorType)
	func loadHelpItems(topic:String, items:[HelpItem])
}

public class Session : NSObject {
	///tried kvo, forced to use notifications
	class Manager: NSObject {
		dynamic var currentSession: Session? {
			didSet { NSNotificationCenter.defaultCenter().postNotificationName(CurrentSessionChangedNotification, object: currentSession) }
		}
	}
	static var manager: Manager = Manager()
	
	let workspace : Workspace
	let wsSource : WebSocketSource
	weak var delegate : SessionDelegate?
	var variablesVisible : Bool = false {
		didSet {
			if variablesVisible && variablesVisible != oldValue {
				requestVariables()
			}
		}
	}
	var helpRegex : NSRegularExpression = {
		return try! NSRegularExpression(pattern: "(help\\(\\\"?([\\w\\d]+)\\\"?\\))\\s*;?\\s?", options: [.DotMatchesLineSeparators])
	}()
	
	private(set) var connectionOpen:Bool = false
	
	init(_ wspace:Workspace, delegate:SessionDelegate?=nil, source:WebSocketSource)
	{
		workspace = wspace
		self.delegate = delegate
		self.wsSource = source
		super.init()
		wsSource.event.open = {
			dispatch_async(dispatch_get_main_queue()) {
				self.connectionOpen = true
				Session.manager.currentSession = self
				self.delegate?.sessionOpened()
			}
		}
		wsSource.event.close = { (code, reason, clear) in
			self.connectionOpen = false
			self.delegate?.sessionClosed()
		}
		wsSource.event.message = { message in
			log.info("got message: \(message as? String)")
			self.delegate?.sessionMessageReceived(JSON.parse(message as! String))
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
	
	//MARK: public reuest methods
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
	
	//MARK: other public methods
	func outputColorForKey(key:OutputColors) -> Color {
		let dict = NSUserDefaults.standardUserDefaults().dictionaryForKey("OutputColors") as! Dictionary<String,String>
		return try! Color(hex: dict[key.rawValue]!)
	}
	
	func noHelpFoundString(topic:String) -> NSAttributedString {
		return NSAttributedString(string: "No help available for '\(topic)'\n", attributes: [NSForegroundColorAttributeName:outputColorForKey(.Help)])
	}
	
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

//MARK: private methods
private extension Session {
	func requestVariables() {
		sendMessage(["cmd":"watchVariables", "watch":variablesVisible])
	}
	
	func handleHelpResults(rsp:ServerResponse) {
		guard case let .Help(topic, items) = rsp else {
			assertionFailure("argument was not a help response")
			return
		}
		self.delegate?.loadHelpItems(topic, items: items)
	}
}
