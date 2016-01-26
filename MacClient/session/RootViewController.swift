//
//  RootViewController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

class RootViewController: AbstractSessionViewController, SessionDelegate, ResponseHandlerDelegate {
	@IBOutlet var progressView: NSProgressIndicator?
	@IBOutlet var statusField: NSTextField?
	var statusTimer:NSTimer?
	dynamic var busy: Bool = false
	dynamic var statusMessage: String = ""
	
	var editor: SessionEditor?
	var outputHandler: SessionOutputHandler?
	var variableHandler: SessionVariableHandler?
	var responseHandler: ResponseHandler?
	
	override func viewWillAppear() {
		super.viewWillAppear()
		editor = firstChildViewController(self)
		outputHandler = firstChildViewController(self)
		variableHandler = firstChildViewController(self)
		do {
			let fm = NSFileManager()
			let cacheUrl = try fm.URLForDirectory(.CachesDirectory, inDomain: .UserDomainMask, appropriateForURL: nil, create: true)
			let imgDirUrl = NSURL(fileURLWithPath: "Rc2/images", isDirectory: true, relativeToURL: cacheUrl)
			imgDirUrl.checkResourceIsReachableAndReturnError(nil) //throws instead of returning error
			responseHandler = ResponseHandler(imageDirectory: imgDirUrl, delegate: self)
		} catch let error {
			log.error("got error creating image cache direcctory:\(error)")
			assertionFailure("failed to create response handler")
		}
	}
	
	override func sessionChanged() {
		session.delegate = self
	}
	
	func startTimer() {
		if statusTimer != nil && statusTimer!.valid { statusTimer?.invalidate() }
		statusTimer = NSTimer.scheduledTimerWithTimeInterval(3.0, target: self, selector: "clearStatus", userInfo: nil, repeats: false)
	}
	
	func clearStatus() {
		statusTimer?.invalidate()
		statusMessage = ""
	}

	//TODO: need to add overlay view that blocks all interaction while busy
	override func appStatusChanged() {
		NSNotificationCenter.defaultCenter().addObserverForName(AppStatusChangedNotification, object: nil, queue: nil) { (note) -> Void in
			guard self.appStatus != nil else {
				log.error("appStatus not set on RootViewController")
				return
			}
			self.busy = (self.appStatus?.busy)!
			self.statusMessage = (self.appStatus?.statusMessage)! as String
			if !self.busy { self.startTimer() }
		}
	}
	
	//MARK: ResponseHandlerDelegate
	func loadHelpItems(topic:String, items:[HelpItem]) {
		
	}
	
	func handleVariableMessage(socketId:Int, delta:Bool, single:Bool, variables:Dictionary<String,JSON>) {
		//need to convert to an objc-compatible dictionary by boxing JSON objects
		var newDict = [String:ObjcBox<JSON>]()
		for (key,value) in variables {
			newDict[key] = ObjcBox(value)
		}
		variableHandler!.handleVariableMessage(socketId, delta: delta, single: single, variables: newDict)
	}

	//MARK: SessionDelegate
	func sessionOpened() {
		
	}
	
	func sessionClosed() {
		
	}
	
	func sessionMessageReceived(response:ServerResponse) {
		if let output = responseHandler?.handleResponse(response) {
			outputHandler?.appendFormattedString(output.string)
			//TODO: do something with the images array?
		}
	}
	
	func sessionErrorReceived(error:ErrorType) {
		
	}
}

@objc protocol SessionEditor {
	
}

@objc protocol SessionVariableHandler {
	///parameter variables: key is a string, value is an ObjcBox of a JSON value
	func handleVariableMessage(socketId:Int, delta:Bool, single:Bool, variables:Dictionary<String,AnyObject>)
}

@objc protocol SessionOutputHandler {
	func appendFormattedString(string:NSAttributedString)
}
