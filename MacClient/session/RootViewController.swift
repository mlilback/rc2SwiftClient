//
//  RootViewController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import CryptoSwift

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
	var savedStateHash: NSData?
	
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
		//save our state on quit and sleep
		NSNotificationCenter.defaultCenter().addObserver(self, selector: "appWillTerminate", name: NSApplicationWillTerminateNotification, object: nil)
		NSNotificationCenter.defaultCenter().addObserver(self, selector:  "saveSessionState", name: NSWorkspaceWillSleepNotification, object:nil)
	}
	
	override func sessionChanged() {
		session.delegate = self
		restoreSessionState()
	}
	
	func startTimer() {
		if statusTimer != nil && statusTimer!.valid { statusTimer?.invalidate() }
		statusTimer = NSTimer.scheduledTimerWithTimeInterval(3.0, target: self, selector: "clearStatus", userInfo: nil, repeats: false)
	}
	
	func clearStatus() {
		statusTimer?.invalidate()
		statusMessage = ""
	}

	func stateFileUrl() throws -> NSURL {
		let appSupportUrl = try NSFileManager.defaultManager().URLForDirectory(.ApplicationSupportDirectory, inDomain: .UserDomainMask, appropriateForURL: nil, create: true)
		let dataDirUrl = NSURL(string: "Rc2/sessions/", relativeToURL: appSupportUrl)?.absoluteURL
		try NSFileManager.defaultManager().createDirectoryAtURL(dataDirUrl!, withIntermediateDirectories: true, attributes: nil)
		let fname = "\(RestServer.sharedInstance.loginSession!.host)--\(session.workspace.userId)--\(session.workspace.wspaceId).plist"
		let furl = NSURL(string:fname, relativeToURL: dataDirUrl)?.absoluteURL
		return furl!
	}
	
	func appWillTerminate() {
		saveSessionState()
	}
	
	func saveSessionState() {
		//save data related to this session
		var dict = [String:AnyObject]()
		dict["outputController"] = outputHandler?.saveSessionState()
		do {
			let data = NSKeyedArchiver.archivedDataWithRootObject(dict)
			//only write to disk if has changed
			let hash = data.sha256()
			if hash != savedStateHash {
				let furl = try stateFileUrl()
				data.writeToURL(furl, atomically: true)
				savedStateHash = hash
			}
		} catch let err {
			log.error("Error saving session state:\(err)")
		}
	}
	
	private func restoreSessionState() {
		do {
			let furl = try stateFileUrl()
			if furl.checkResourceIsReachableAndReturnError(nil) {
				let data = NSData(contentsOfURL: furl)
				if let dict = NSKeyedUnarchiver.unarchiveObjectWithData(data!) as! [String:AnyObject]? {
					if let ostate = dict["outputController"] as! [String : AnyObject]? {
						outputHandler?.restoreSessionState(ostate)
					}
					savedStateHash = data?.sha256()
				}
			}
		} catch let err {
			log.error("error restoring session state:\(err)")
		}
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

	func attributedStringWithImage(image:SessionImage) -> NSAttributedString {
		let data = NSKeyedArchiver.archivedDataWithRootObject(image)
		let file = NSFileWrapper(regularFileWithContents: data)
		file.filename = image.name
		file.preferredFilename = image.name
		let attachment = NSTextAttachment(fileWrapper: file)
		let cell = NSTextAttachmentCell(imageCell: NSImage(named: "graph"))
		cell.image?.size = NSMakeSize(48, 48)
		attachment.attachmentCell = cell
		let str = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))
		str.addAttribute(NSToolTipAttributeName, value: image.name, range: NSMakeRange(0,1))
		return str
	}
	
	//MARK: SessionDelegate
	func sessionOpened() {
		
	}
	
	func sessionClosed() {
		
	}
	
	func sessionMessageReceived(response:ServerResponse) {
		if let astr = responseHandler?.handleResponse(response) {
			outputHandler?.appendFormattedString(astr)
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
	func saveSessionState() -> AnyObject
	func restoreSessionState(state:[String:AnyObject])
}
