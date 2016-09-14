//
//  RootViewController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import CryptoSwift
import SwiftyJSON
import os

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
	var statusTimer:Timer?
	dynamic var busy: Bool = false
	dynamic var statusMessage: String = ""
	var sessionClosedHandler:((Void)->Void)?
	
	fileprivate var dimmingView:DimmingView?
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
		NotificationCenter.default.addObserver(self, selector: #selector(RootViewController.windowWillClose(_:)), name: NSNotification.Name.NSWindowWillClose, object:view.window!)
		//create dimming view
		dimmingView = DimmingView(frame: view.bounds)
		view.addSubview(dimmingView!)
		(view as! RootView).dimmingView = dimmingView //required to block clicks to subviews
		//we have to wait until next time through event loop to set first responder
		self.performSelector(onMainThread: #selector(RootViewController.setupResponder), with: nil, waitUntilDone: false)

	}
	
	func windowWillClose(_ note:Notification) {
		if sessionOptional?.connectionOpen ?? false && (note.object as? NSWindow == view.window) {
			sessionController?.close()
			sessionController = nil
		}
	}
	
	override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		switch(menuItem.action) {
		case (#selector(FileHandler.promptToImportFiles(_:)))?:
			return fileHandler!.validateMenuItem(menuItem)
		case (#selector(ManageFontMenu.showFonts(_:)))?:
			if let fontHandler = currentFontUser(view.window?.firstResponder) {
				guard fontHandler.fontsEnabled() else { return false }
				updateFontFaceMenu(menuItem.submenu!, fontUser:fontHandler)
				return true
			}
			return false
		case (#selector(ManageFontMenu.showFontSizes(_:)))?:
			if let fontHandler = currentFontUser(view.window?.firstResponder) {
				guard fontHandler.fontsEnabled() else { return false }
				updateFontSizeMenu(menuItem.submenu!, fontUser:fontHandler)
				return true
			}
			return false
		case (#selector(ManageFontMenu.adjustFontSize(_:)))?:
			return true
		default:
			return false
		}
	}

	func setupResponder() {
		view.window?.makeFirstResponder(outputHandler?.initialFirstResponder())
	}
	
	func handlesToolbarItem(_ item: NSToolbarItem) -> Bool {
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
					item.isEnabled = self.responderChainContains(self)
				}
			}
			return true
		}
		return false
	}
	
	//MARK: - status display/timer
	func startTimer() {
		if statusTimer?.isValid ?? false { statusTimer?.invalidate() }
		statusTimer = Timer.scheduledTimer(timeInterval: 3.0, target: self, selector: #selector(RootViewController.clearStatus), userInfo: nil, repeats: false)
	}
	
	func clearStatus() {
		statusTimer?.invalidate()
		statusMessage = ""
	}

	func receivedStatusNotification(_ note:Notification) {
		guard self.appStatus != nil else {
			os_log("appStatus not set on RootViewController", type:.error)
			return
		}
		self.busy = (self.appStatus?.busy)!
		self.statusMessage = (self.appStatus?.statusMessage) ?? ""
		//hide/show dimmingView only if
		if self.editor?.view.isHiddenOrHasHiddenAncestor == false {
			if self.busy {
				self.dimmingView?.isHidden = false
				self.formerFirstResponder = self.view.window?.firstResponder
				self.view.window?.makeFirstResponder(self.dimmingView)
			} else {
				self.dimmingView?.isHidden = true
				self.startTimer()
				self.view.window?.makeFirstResponder(self.formerFirstResponder)
//					self.dimmingView?.animator().hidden = true
			}
		}
	}
	
	override func appStatusChanged() {
		NotificationCenter.default.addObserver(self, selector: #selector(RootViewController.receivedStatusNotification(_:)), name: NSNotification.Name(rawValue: Notifications.AppStatusChanged), object: nil)
	}
}

//MARK: - actions
extension RootViewController {
	@IBAction func clearFileCache(_ sender:AnyObject) {
		sessionController?.clearFileCache()
	}
	
	@IBAction func promptToImportFiles(_ sender:AnyObject?) {
		fileHandler?.promptToImportFiles(sender)
	}
}

//MARK: - fonts
extension RootViewController {
	@IBAction func showFonts(_ sender: AnyObject) {
		//do nothing, just a place holder for menu validation
	}
	
	@IBAction func showFontSizes(_ sender: AnyObject) {
		//do nothing. just placeholder for menu validation
	}
	
	@IBAction func adjustFontSize(_ sender: NSMenuItem) {
		let fsize = sender.tag
		if fsize < 9 {
			//TODO: implement custom font size dialog
		} else {
			let fontUser = currentFontUser(view.window!.firstResponder)
			fontUser?.currentFontDescriptor = fontUser!.currentFontDescriptor.withSize(CGFloat(fsize))
		}
	}
	
	func updateFontFaceMenu(_ menu:NSMenu, fontUser:UsesAdjustableFont) {
		menu.removeAllItems()
		//we want regular weight monospaced fonts
		let traits = [NSFontSymbolicTrait: NSFontMonoSpaceTrait, NSFontWeightTrait: 0]
		let attrs = [NSFontTraitsAttribute: traits]
		let filterDesc = NSFontDescriptor(fontAttributes: attrs)
		//get matching fonts and sort them by name
		let fonts = filterDesc.matchingFontDescriptors(withMandatoryKeys: nil).sorted {
			($0.object(forKey: NSFontNameAttribute) as! String).lowercased() < ($1.object(forKey: NSFontNameAttribute) as! String).lowercased()
		}
		//now add menu items for them
		for aFont in fonts {
			let menuItem = NSMenuItem(title: aFont.visibleName, action: #selector(UsesAdjustableFont.fontChanged), keyEquivalent: "")
			menuItem.representedObject = aFont
			if fontUser.currentFontDescriptor.fontName == aFont.fontName {
				menuItem.state = NSOnState
				menuItem.isEnabled = false
			}
			menu.addItem(menuItem)
		}
	}

	func updateFontSizeMenu(_ menu:NSMenu, fontUser:UsesAdjustableFont) {
		var markedCurrent = false
		var customItem:NSMenuItem?
		let curSize = Int(fontUser.currentFontDescriptor.pointSize)
		for anItem in menu.items {
			anItem.state = NSOffState
			if anItem.tag == curSize {
				anItem.state = NSOnState
				markedCurrent = true
			} else if anItem.tag == 0 {
				customItem = anItem
			}
			anItem.isEnabled = true
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
		dict["editor"] = editor?.saveState() as AnyObject?
		return dict
	}
	
	func restoreState(_ state:[String:AnyObject]) {
		editor?.restoreState(state["editor"] as! [String:AnyObject])
	}
}

//MARK: - FileViewControllerDelegate
extension RootViewController: FileViewControllerDelegate {
	func fileSelectionChanged(_ file:File?) {
		if nil == file {
			self.editor?.fileSelectionChanged(nil)
			self.outputHandler?.showFile(0)
		} else if file!.fileType.isSourceFile {
			self.editor?.fileSelectionChanged(file)
		} else {
			self.outputHandler?.showFile(file!.fileId)
		}
	}
	
	func renameFile(_ file:File, to:String) {
		//TODO:implement renameFile
	}

	func importFiles(_ files:[URL]) {
		
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
		layer!.backgroundColor = NSColor.black.withAlphaComponent(0.1).cgColor
		view.addConstraint(leadingAnchor.constraint(equalTo: view.leadingAnchor))
		view.addConstraint(trailingAnchor.constraint(equalTo: view.trailingAnchor))
		view.addConstraint(topAnchor.constraint(equalTo: view.topAnchor))
		view.addConstraint(bottomAnchor.constraint(equalTo: view.bottomAnchor))
		isHidden = true
	}

	override func hitTest(_ aPoint: NSPoint) -> NSView? {
		if !isHidden {
			return self
		}
		return super.hitTest(aPoint)
	}
}

class RootView: NSView {
	var dimmingView:DimmingView?
	//if dimmingView is visible, block all subviews from getting clicks
	override func hitTest(_ aPoint: NSPoint) -> NSView? {
		if dimmingView != nil && !dimmingView!.isHidden {
			return self
		}
		return super.hitTest(aPoint)
	}
}
