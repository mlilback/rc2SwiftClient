//
//  RootViewController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import CryptoSwift
import SwiftyJSON

class RootViewController: AbstractSessionViewController, ToolbarItemHandler, ManageFontMenu
{
	//MARK: - properties
	var restServer: RestServer? { didSet {
		let variableHandler:VariableHandler = firstChildViewController(self)!
		sessionController = SessionController(session: restServer!.session!, delegate: self, outputHandler: outputHandler!, variableHandler:variableHandler)
		outputHandler?.sessionController = sessionController
	} }
	var sessionController: SessionController?
	
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
	weak var fileHandler: FileHandler?
	var formerFirstResponder:NSResponder? //used to restore first responder when dimmingview goes away
	
	deinit {
		sessionController?.close()
	}
	
	//MARK: - Lifecycle
	override func viewWillAppear() {
		super.viewWillAppear()
		guard editor == nil else { return } //only run once
		editor = firstChildViewController(self)
		outputHandler = firstChildViewController(self)
		fileHandler = firstChildViewController(self)
		let concreteFH = fileHandler as? SidebarFileController
		if concreteFH != nil {
			concreteFH!.delegate = self
		}
	}
	
	override func viewDidAppear() {
		super.viewDidAppear()
		self.hookupToToolbarItems(self, window: view.window!)
		NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(RootViewController.windowWillClose(_:)), name: NSWindowWillCloseNotification, object:view.window!)
		//create dimming view
		dimmingView = DimmingView(frame: view.bounds)
		view.addSubview(dimmingView!)
		(view as! RootView).dimmingView = dimmingView //required to block clicks to subviews
		//we have to wait until next time through event loop to set first responder
		self.performSelectorOnMainThread(#selector(RootViewController.setupResponder), withObject: nil, waitUntilDone: false)

	}
	
	func windowWillClose(note:NSNotification) {
		if sessionOptional?.connectionOpen ?? false && (note.object as? NSWindow == view.window) {
			sessionController?.close()
			sessionController = nil
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
		case #selector(ManageFontMenu.showFontSizes(_:)):
			if let fontHandler = currentFontUser(view.window?.firstResponder) {
				guard fontHandler.fontsEnabled() else { return false }
				updateFontSizeMenu(menuItem.submenu!, fontUser:fontHandler)
				return true
			}
			return false
		case #selector(ManageFontMenu.adjustFontSize(_:)):
			return true
		default:
			return false
		}
	}

	func setupResponder() {
		view.window?.makeFirstResponder(outputHandler?.initialFirstResponder())
	}
	
	func handlesToolbarItem(item: NSToolbarItem) -> Bool {
		if item.itemIdentifier == "search" {
			searchButton = item.view as! NSSegmentedControl?
			TargetActionBlock() { [weak self] sender in
				if self!.responderChainContains(self!.editor!)  {
					self!.editor?.performTextFinderAction(sender)
				} else {
					self!.outputHandler?.prepareForSearch()
				}
			}.installInControl(searchButton!)
			if let myItem = item as? ValidatingToolbarItem {
				myItem.validationHandler = { item in
					item.enabled = self.responderChainContains(self)
				}
			}
			return true
		}
		return false
	}
	
	//MARK: - status display/timer
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
		self.statusMessage = (self.appStatus?.statusMessage) ?? ""
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
		NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(RootViewController.receivedStatusNotification(_:)), name: Notifications.AppStatusChanged, object: nil)
	}
}

//MARK: - actions
extension RootViewController {
	@IBAction func clearFileCache(sender:AnyObject) {
		sessionController?.clearFileCache()
	}
	
	@IBAction func promptToImportFiles(sender:AnyObject?) {
		fileHandler?.promptToImportFiles(sender)
	}
}

//MARK: - fonts
extension RootViewController {
	@IBAction func showFonts(sender: AnyObject) {
		//do nothing, just a place holder for menu validation
	}
	
	@IBAction func showFontSizes(sender: AnyObject) {
		//do nothing. just placeholder for menu validation
	}
	
	@IBAction func adjustFontSize(sender: NSMenuItem) {
		let fsize = sender.tag
		if fsize < 9 {
			//TODO: implement custom font size dialog
		} else {
			let fontUser = currentFontUser(view.window!.firstResponder)
			fontUser?.currentFontDescriptor = fontUser!.currentFontDescriptor.fontDescriptorWithSize(CGFloat(fsize))
		}
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

	func updateFontSizeMenu(menu:NSMenu, fontUser:UsesAdjustableFont) {
		var markedCurrent = false
		var customItem:NSMenuItem?
		let curSize = Int(fontUser.currentFontDescriptor.pointSize)
		for anItem in menu.itemArray {
			anItem.state = NSOffState
			if anItem.tag == curSize {
				anItem.state = NSOnState
				markedCurrent = true
			} else if anItem.tag == 0 {
				customItem = anItem
			}
			anItem.enabled = true
		}
		if !markedCurrent {
			customItem?.state = NSOnState
		}
	}
}

//MARK: - SessionControllerDelegate
extension RootViewController: SessionControllerDelegate {
	func sessionClosed() {
		self.sessionClosedHandler?()
	}
	
	func filesRefreshed() {
		fileHandler?.filesRefreshed(nil)
	}

	func saveState() -> [String:AnyObject] {
		var dict = [String:AnyObject]()
		dict["editor"] = editor?.saveState()
		return dict
	}
	
	func restoreState(state:[String:AnyObject]) {
		editor?.restoreState(state["editor"] as! [String:AnyObject])
	}
}

//MARK: - FileViewControllerDelegate
extension RootViewController: FileViewControllerDelegate {
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
}


//MARK: -
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
