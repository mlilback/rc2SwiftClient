//
//  RootViewController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import CryptoSwift

class RootViewController: AbstractSessionViewController, SessionDelegate, ResponseHandlerDelegate, ToolbarItemHandler
{
	@IBOutlet var progressView: NSProgressIndicator?
	@IBOutlet var statusField: NSTextField?
	var searchButton: NSSegmentedControl?
	var statusTimer:NSTimer?
	dynamic var busy: Bool = false
	dynamic var statusMessage: String = ""
	
	weak var editor: SessionEditorController?
	weak var outputHandler: SessionOutputHandler?
	weak var variableHandler: SessionVariableHandler?
	var responseHandler: ResponseHandler?
	var savedStateHash: NSData?
	var imgCache: ImageCache = ImageCache() { didSet { outputHandler?.imageCache = imgCache } }
	
	override func viewWillAppear() {
		super.viewWillAppear()
		editor = firstChildViewController(self)
		outputHandler = firstChildViewController(self)
		outputHandler?.imageCache = imgCache
		variableHandler = firstChildViewController(self)
		responseHandler = ResponseHandler(delegate: self)
		//save our state on quit and sleep
		NSNotificationCenter.defaultCenter().addObserver(self, selector: "appWillTerminate", name: NSApplicationWillTerminateNotification, object: nil)
		NSNotificationCenter.defaultCenter().addObserver(self, selector:  "saveSessionState", name: NSWorkspaceWillSleepNotification, object:nil)
	}
	
	override func viewDidAppear() {
		super.viewDidAppear()
		self.hookupToToolbarItems(self, window: view.window!)
	}
	
	override func sessionChanged() {
		session.delegate = self
		imgCache.workspace = session.workspace
		restoreSessionState()
	}
	
	func handlesToolbarItem(item: NSToolbarItem) -> Bool {
		if item.itemIdentifier == "search" {
			searchButton = item.view as! NSSegmentedControl?
			searchButton?.target = self
			searchButton?.action = "searchClicked:"
			if let myItem = item as? SearchToolbarItem {
				myItem.rootController = self
			}
			return true
		}
		return false
	}

	func validateSearchButton(button:SearchToolbarItem) {
		button.enabled = true
	}
	
	func searchClicked(sender:AnyObject?) {
		if inResponderChain(editor!) {
			editor?.performTextFinderAction(sender)
		} else {
			outputHandler?.prepareForSearch()
		}
	}
	
	func inResponderChain(responder:NSResponder) -> Bool {
		var curResponder = view.window?.firstResponder
		while curResponder != nil {
			if curResponder == responder { return true }
			curResponder = curResponder?.nextResponder
		}
		return false
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
		//can't save w/o a session (didn't leave workspace tab)
		if sessionOptional != nil {
			saveSessionState()
		}
	}
	
	func saveSessionState() {
		//save data related to this session
		var dict = [String:AnyObject]()
		dict["outputController"] = outputHandler?.saveSessionState()
		dict["imageCache"] = imgCache
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
					if let ic = dict["imageCache"] as! ImageCache? {
						imgCache = ic
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
	//TODO: implement loadHelpItems
	func loadHelpItems(topic:String, items:[HelpItem]) {
		
	}
	
	//TODO: implement handleFileUpdate
	func handleFileUpdate(file:File, change:FileChangeType) {
		
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
	
	func cacheImages(images:[SessionImage]) {
		imgCache.cacheImagesFromServer(images)
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
	
	//TODO: impelment sessionReceivedError
	func sessionErrorReceived(error:ErrorType) {
		
	}
}

class SearchToolbarItem: NSToolbarItem {
	var rootController: RootViewController?
	override func validate() {
		rootController?.validateSearchButton(self)
	}
}
