//
//  RootViewController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import CryptoSwift
import SwiftyJSON

class RootViewController: AbstractSessionViewController, SessionDelegate, ResponseHandlerDelegate, FileViewControllerDelegate, ToolbarItemHandler, ManageFontMenu
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
	
	deinit {
		sessionOptional?.close()
	}
	
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
		NSNotificationCenter.defaultCenter().addObserver(self, selector:  #selector(RootViewController.windowWillClose(_:)), name: NSWindowWillCloseNotification, object:view.window!)
		//create dimming view
		dimmingView = DimmingView(frame: view.bounds)
		view.addSubview(dimmingView!)
		(view as! RootView).dimmingView = dimmingView //required to block clicks to subviews
		//we have to wait until next time through event loop to set first responder
		self.performSelectorOnMainThread(#selector(RootViewController.setupResponder), withObject: nil, waitUntilDone: false)
	}
	
	func windowWillClose(note:NSNotification) {
		if sessionOptional?.connectionOpen ?? false && (note.object as? NSWindow == view.window) {
			session.close()
		}
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
		case #selector(ManageFontMenu.showFonts(_:)):
			if let fontHandler = currentFontUser(view.window?.firstResponder) {
				guard fontHandler.fontsEnabled() else { return false }
				updateFontFaceMenu(menuItem.submenu!, fontUser:fontHandler)
				return true
			}
			return false
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
		outputHandler?.session = session
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
	
	//MARK: - fonts
	
	func showFonts(sender: AnyObject) {
		//do nothing, just a place holder for menu validation
	}
	
	func updateFontFaceMenu(menu:NSMenu, fontUser:UsesAdjustableFont) {
		menu.removeAllItems()
		//we want regular weight monospaced fonts
		let traits = [NSFontSymbolicTrait: NSFontMonoSpaceTrait, NSFontWeightTrait: 0]
		let attrs = [NSFontTraitsAttribute: traits]
		let filterDesc = NSFontDescriptor(fontAttributes: attrs)
		//get matching fonts and sort them by name
		let fonts = filterDesc.matchingFontDescriptorsWithMandatoryKeys(nil).sort {
			($0.objectForKey(NSFontNameAttribute) as! String).lowercaseString < ($1.objectForKey(NSFontNameAttribute) as! String).lowercaseString
		}
		//now add menu items for them
		for aFont in fonts {
			let menuItem = NSMenuItem(title: aFont.visibleName, action: #selector(UsesAdjustableFont.fontChanged), keyEquivalent: "")
			menuItem.representedObject = aFont
			if fontUser.currentFontDescriptor.fontName == aFont.fontName {
				menuItem.state = NSOnState
				menuItem.enabled = false
			}
			menu.addItem(menuItem)
		}
	}
	
	//MARK: - ResponseHandlerDelegate
	//TODO: implement loadHelpItems
	func loadHelpItems(topic:String, items:[HelpItem]) {
		
	}
	
	func handleFileUpdate(file:File, change:FileChangeType) {
		log.info("got file update \(file.fileId) v\(file.version)")
		session.fileHandler.handleFileUpdate(file, change: change)
	}
	
	func handleVariableMessage(socketId:Int, single:Bool, variables:[Variable]) {
		//need to convert to an objc-compatible dictionary by boxing JSON objects
//		var newDict = [String:ObjcBox<JSON>]()
//		for (key,value) in variables {
//			newDict[key] = ObjcBox(value)
//		}
		variableHandler!.handleVariableMessage(socketId, single: single, variables: variables)
	}
	
	func handleVariableDeltaMessage(socketId: Int, assigned: [Variable], removed: [String]) {
		variableHandler!.handleVariableDeltaMessage(socketId, assigned: assigned, removed: removed)
	}

	func consoleAttachment(forImage image:SessionImage) -> ConsoleAttachment {
		return MacConsoleAttachment(image:image)
	}
	
	func consoleAttachment(forFile file:File) -> ConsoleAttachment {
		return MacConsoleAttachment(file:file)
	}
	
	func attributedStringForInputFile(fileId:Int) -> NSAttributedString {
		let file = session.workspace.fileWithId(fileId)
		return NSAttributedString(string: "[\(file!.name)]")
	}
	
	func cacheImages(images:[SessionImage]) {
		imgCache.cacheImagesFromServer(images)
	}
	
	func showFile(fileId:Int) {
		outputHandler?.showFile(fileId)
	}

	//MARK:- FileViewControllerDelegate
	func fileSelectionChanged(file:File?) {
		if nil == file {
			self.editor?.fileSelectionChanged(nil)
			self.outputHandler?.showFile(0)
		} else if file!.fileType.isSourceFile {
			self.editor?.fileSelectionChanged(file)
		} else {
			self.outputHandler?.showFile(file!.fileId)
		}
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
		if case ServerResponse.ShowOutput( _, let updatedFile) = response {
			if updatedFile != session.workspace.fileWithId(updatedFile.fileId) {
				//need to refetch file from server, then show it
				let prog = session.fileHandler.updateFile(updatedFile, withData: nil)
				prog?.rc2_addCompletionHandler() {
					if let astr = self.responseHandler?.handleResponse(response) {
						self.outputHandler?.appendFormattedString(astr, type: response.isEcho() ? .Input : .Default)
					}
//					self.outputHandler?.appendFormattedString(self.consoleAttachment(forFile:updatedFile).serializeToAttributedString(), type:.Default)
				}
				return
			}
		}
		if let astr = responseHandler?.handleResponse(response) {
			outputHandler?.appendFormattedString(astr, type: response.isEcho() ? .Input : .Default)
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
