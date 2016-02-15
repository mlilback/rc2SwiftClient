//
//  RootViewController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import CryptoSwift

class RootViewController: AbstractSessionViewController, SessionDelegate, ResponseHandlerDelegate, FileViewControllerDelegate, ToolbarItemHandler
{
	//MARK: properties
	@IBOutlet var progressView: NSProgressIndicator?
	@IBOutlet var statusField: NSTextField?
	var searchButton: NSSegmentedControl?
	var statusTimer:NSTimer?
	dynamic var busy: Bool = false
	dynamic var statusMessage: String = ""
	
	private var dimmingView:NSView?
	weak var editor: SessionEditorController?
	weak var outputHandler: OutputHandler?
	weak var variableHandler: VariableHandler?
	weak var fileHandler: FileHandler?
	var responseHandler: ResponseHandler?
	var savedStateHash: NSData?
	var imgCache: ImageCache = ImageCache() { didSet { outputHandler?.imageCache = imgCache } }
	
	//MARK: AppKit
	override func viewWillAppear() {
		super.viewWillAppear()
		editor = firstChildViewController(self)
		outputHandler = firstChildViewController(self)
		outputHandler?.imageCache = imgCache
		variableHandler = firstChildViewController(self)
		responseHandler = ResponseHandler(delegate: self)
		fileHandler = firstChildViewController(self)
		let concreteFH = fileHandler as? FileViewController
		if concreteFH != nil {
			concreteFH!.delegate = self
		}
		//save our state on quit and sleep
		NSNotificationCenter.defaultCenter().addObserver(self, selector: "appWillTerminate", name: NSApplicationWillTerminateNotification, object: nil)
		NSNotificationCenter.defaultCenter().addObserver(self, selector:  "saveSessionState", name: NSWorkspaceWillSleepNotification, object:nil)
	}
	
	override func viewDidAppear() {
		super.viewDidAppear()
		self.hookupToToolbarItems(self, window: view.window!)
		//create dimming view
		let dview = NSView(frame: view.bounds)
		dimmingView = dview
		dview.translatesAutoresizingMaskIntoConstraints = false
		dview.wantsLayer = true
		dview.layer!.backgroundColor = NSColor.blackColor().colorWithAlphaComponent(0.1).CGColor
		view.addSubview(dview)
		view.addConstraint(dview.leadingAnchor.constraintEqualToAnchor(view.leadingAnchor))
		view.addConstraint(dview.trailingAnchor.constraintEqualToAnchor(view.trailingAnchor))
		view.addConstraint(dview.topAnchor.constraintEqualToAnchor(view.topAnchor))
		view.addConstraint(dview.bottomAnchor.constraintEqualToAnchor(view.bottomAnchor))
		dview.hidden = true
		//we have to wait until next time through event loop to set first responder
		self.performSelectorOnMainThread("setupResponder", withObject: nil, waitUntilDone: false)
	}
	
	func setupResponder() {
		view.window?.makeFirstResponder(outputHandler?.initialFirstResponder())
	}
	
	override func sessionChanged() {
		session.delegate = self
		imgCache.workspace = session.workspace
		restoreSessionState()
	}
	
	func handlesToolbarItem(item: NSToolbarItem) -> Bool {
		if item.itemIdentifier == "search" {
			searchButton = item.view as! NSSegmentedControl?
			TargetActionBlock() { [weak self] sender in
				if self!.inResponderChain(self!.editor!)  {
					self!.editor?.performTextFinderAction(sender)
				} else {
					self!.outputHandler?.prepareForSearch()
				}
			}.installInControl(searchButton!)
			if let myItem = item as? ValidatingToolbarItem {
				myItem.validationHandler = { item in
					item.enabled = self.inResponderChain(self)
				}
			}
			return true
		}
		return false
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
			//hide/show dimmingView only if
			if self.editor?.view.hiddenOrHasHiddenAncestor == false {
				if self.busy {
					self.dimmingView?.hidden = false
				} else {
					self.startTimer()
					self.dimmingView?.animator().hidden = true
				}
			}
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

	//MARK:FileViewControllerDelegate
	func fileSelectionChanged(file:File?) {
		var contents:String?
		if let theFile = file {
			session.fileHandler.contentsOfFile(theFile).onComplete { result in
				switch(result) {
					case .Success(let val):
						contents = String(data: val!, encoding: NSUTF8StringEncoding)
					case .Failure(let err):
						log.warning("got error \(err)")
				}
				self.editor?.fileSelectionChanged(file, text: contents)
			}
		} else {
			self.editor?.fileSelectionChanged(nil, text: "")
		}
	}
	
	@IBAction func clearFileCache(sender:AnyObject) {
		session.fileHandler.fileCache.flushCacheForWorkspace(session.workspace)
	}
	
	func renameFile(file:File, to:String) {
		//TODO:implement
	}

	
	//MARK: SessionDelegate
	func sessionOpened() {
		
	}
	
	func sessionClosed() {
		
	}
	
	func sessionFilesLoaded(session:Session) {
		fileHandler?.filesRefreshed()
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
