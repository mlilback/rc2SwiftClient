//
//  RootViewController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import CryptoSwift
import SwiftyJSON

class RootViewController: AbstractSessionViewController, SessionDelegate, ResponseHandlerDelegate, FileViewControllerDelegate, ToolbarItemHandler
{
	//MARK: - properties
	@IBOutlet var progressView: NSProgressIndicator?
	@IBOutlet var statusField: NSTextField?
	var searchButton: NSSegmentedControl?
	var statusTimer:NSTimer?
	dynamic var busy: Bool = false
	dynamic var statusMessage: String = ""
	var sessionClosedHandler:((Void)->Void)?
	
	private var dimmingView:DimmingView?
	weak var editor: SessionEditorController?
	weak var outputHandler: OutputHandler?
	weak var variableHandler: VariableHandler?
	weak var fileHandler: FileHandler?
	var responseHandler: ResponseHandler?
	var savedStateHash: NSData?
	var imgCache: ImageCache = ImageCache() { didSet { outputHandler?.imageCache = imgCache } }
	var formerFirstResponder:NSResponder? //used to restore first responder when dimmingview goes away
	
	//MARK: - Lifecycle
	override func viewWillAppear() {
		super.viewWillAppear()
		guard editor == nil else { return } //only run once
		editor = firstChildViewController(self)
		outputHandler = firstChildViewController(self)
		outputHandler?.imageCache = imgCache
		variableHandler = firstChildViewController(self)
		responseHandler = ResponseHandler(delegate: self)
		fileHandler = firstChildViewController(self)
		let concreteFH = fileHandler as? SidebarFileController
		if concreteFH != nil {
			concreteFH!.delegate = self
		}
		//save our state on quit and sleep
		NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(RootViewController.appWillTerminate), name: NSApplicationWillTerminateNotification, object: nil)
		NSNotificationCenter.defaultCenter().addObserver(self, selector:  #selector(OutputHandler.saveSessionState), name: NSWorkspaceWillSleepNotification, object:nil)
	}
	
	override func viewDidAppear() {
		super.viewDidAppear()
		self.hookupToToolbarItems(self, window: view.window!)
		//create dimming view
		dimmingView = DimmingView(frame: view.bounds)
		view.addSubview(dimmingView!)
		(view as! RootView).dimmingView = dimmingView //required to block clicks to subviews
		//we have to wait until next time through event loop to set first responder
		self.performSelectorOnMainThread(#selector(RootViewController.setupResponder), withObject: nil, waitUntilDone: false)
	}
	
	func appWillTerminate() {
		//can't save w/o a session (didn't leave workspace tab)
		if sessionOptional != nil {
			saveSessionState()
		}
	}
	
	override func validateMenuItem(menuItem: NSMenuItem) -> Bool {
		switch(menuItem.action) {
		case #selector(FileHandler.promptToImportFiles(_:)):
			return fileHandler!.validateMenuItem(menuItem)
		default:
			return false
		}
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
		if statusTimer?.valid ?? false { statusTimer?.invalidate() }
		statusTimer = NSTimer.scheduledTimerWithTimeInterval(3.0, target: self, selector: #selector(RootViewController.clearStatus), userInfo: nil, repeats: false)
	}
	
	func clearStatus() {
		statusTimer?.invalidate()
		statusMessage = ""
	}

	func receivedStatusNotification(note:NSNotification) {
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
				self.formerFirstResponder = self.view.window?.firstResponder
				self.view.window?.makeFirstResponder(self.dimmingView)
			} else {
				self.dimmingView?.hidden = true
				self.startTimer()
				self.view.window?.makeFirstResponder(self.formerFirstResponder)
//					self.dimmingView?.animator().hidden = true
			}
		}
	}
	
	override func appStatusChanged() {
		NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(RootViewController.receivedStatusNotification(_:)), name: AppStatusChangedNotification, object: nil)
	}
	
	func hideDimmingView() {
	}
	
	//MARK: - actions
	@IBAction func clearFileCache(sender:AnyObject) {
		session.fileHandler.fileCache.flushCacheForWorkspace(session.workspace)
	}
	
	@IBAction func promptToImportFiles(sender:AnyObject?) {
		fileHandler?.promptToImportFiles(sender)
	}

	//MARK: - save/restore
	func stateFileUrl() throws -> NSURL {
		let appSupportUrl = try NSFileManager.defaultManager().URLForDirectory(.ApplicationSupportDirectory, inDomain: .UserDomainMask, appropriateForURL: nil, create: true)
		let dataDirUrl = NSURL(string: "Rc2/sessions/", relativeToURL: appSupportUrl)?.absoluteURL
		try NSFileManager.defaultManager().createDirectoryAtURL(dataDirUrl!, withIntermediateDirectories: true, attributes: nil)
		let fname = "\(RestServer.sharedInstance.loginSession!.host)--\(session.workspace.userId)--\(session.workspace.wspaceId).plist"
		let furl = NSURL(string:fname, relativeToURL: dataDirUrl)?.absoluteURL
		return furl!
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
	
	//MARK: - ResponseHandlerDelegate
	//TODO: implement loadHelpItems
	func loadHelpItems(topic:String, items:[HelpItem]) {
		
	}
	
	//TODO: implement handleFileUpdate
	func handleFileUpdate(file:File, change:FileChangeType) {
		log.info("got file update \(file.fileId)")
	}
	
	func showOutputFile(updatedFile:File, queryId:Int) {
		//TODO: show file output
		log.info("show filed output: \(updatedFile)")
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
	
	func attributedStringWithFileId(fileId:Int) -> NSAttributedString {
		return NSAttributedString(string: "")
	}
	
	func cacheImages(images:[SessionImage]) {
		imgCache.cacheImagesFromServer(images)
	}

	//MARK:- FileViewControllerDelegate
	func fileSelectionChanged(file:File?) {
		self.editor?.fileSelectionChanged(file)
	}
	
	func renameFile(file:File, to:String) {
		//TODO:implement renameFile
	}

	func importFiles(files:[NSURL]) {
		
	}
	
	//MARK: - SessionDelegate
	func sessionOpened() {
		
	}
	
	func sessionClosed() {
		sessionClosedHandler?()
	}
	
	func sessionFilesLoaded(session:Session) {
		fileHandler?.filesRefreshed(nil)
	}
	
	func sessionMessageReceived(response:ServerResponse) {
		//TODO need 
		if let astr = responseHandler?.handleResponse(response) {
			outputHandler?.appendFormattedString(astr)
		}
	}
	
	//TODO: impelment sessionErrorReceived
	func sessionErrorReceived(error:ErrorType) {
		
	}
}

class DimmingView: NSView {
	override required init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
	}

	required init?(coder: NSCoder) {
	    fatalError("DimmingView does not support NSCoding")
	}

	override func viewDidMoveToSuperview() {
		guard let view = superview else { return }
		translatesAutoresizingMaskIntoConstraints = false
		wantsLayer = true
		layer!.backgroundColor = NSColor.blackColor().colorWithAlphaComponent(0.1).CGColor
		view.addConstraint(leadingAnchor.constraintEqualToAnchor(view.leadingAnchor))
		view.addConstraint(trailingAnchor.constraintEqualToAnchor(view.trailingAnchor))
		view.addConstraint(topAnchor.constraintEqualToAnchor(view.topAnchor))
		view.addConstraint(bottomAnchor.constraintEqualToAnchor(view.bottomAnchor))
		hidden = true
	}

	override func hitTest(aPoint: NSPoint) -> NSView? {
		if !hidden {
			return self
		}
		return super.hitTest(aPoint)
	}
}

class RootView: NSView {
	var dimmingView:DimmingView?
	//if dimmingView is visible, block all subviews from getting clicks
	override func hitTest(aPoint: NSPoint) -> NSView? {
		if dimmingView != nil && !dimmingView!.hidden {
			return self
		}
		return super.hitTest(aPoint)
	}
}
