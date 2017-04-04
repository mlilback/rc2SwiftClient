//
//  RootViewController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import CryptoSwift
import Freddy
import os
import ReactiveSwift
import Networking

extension Selector {
	static let promptToImport = #selector(RootViewController.promptToImportFiles(_:))
	static let switchSidebarTab = #selector(RootViewController.switchSidebarTab(_:))
	static let switchOutputTab = #selector(RootViewController.switchOutputTab(_:))
}

let MaxEditableFileSize: Int = 1024 * 1024 // 1 MB

class RootViewController: AbstractSessionViewController, ToolbarItemHandler
{
	// MARK: - properties
	var sessionController: SessionController?
	
	var searchButton: NSSegmentedControl?
	var statusTimer: Timer?
	var sessionClosedHandler: (() -> Void)?
	
	fileprivate var progressDisposable: Disposable?
	fileprivate var dimmingView: DimmingView?
	weak var editor: SessionEditorController?
	weak var splitController: SessionSplitController?
	weak var outputHandler: OutputHandler?
	weak var fileHandler: FileHandler?
	var formerFirstResponder: NSResponder? //used to restore first responder when dimmingview goes away
	
	deinit {
		sessionController?.close()
	}
	
	override func sessionChanged() {
		let variableHandler: VariableHandler = firstChildViewController(self)!
		sessionController = SessionController(session: session, delegate: self, outputHandler: outputHandler!, variableHandler:variableHandler)
		outputHandler?.sessionController = sessionController
	}
	
	// MARK: - Lifecycle
	override func viewWillAppear() {
		super.viewWillAppear()
		guard editor == nil else { return } //only run once
		editor = firstChildViewController(self)
		splitController = firstChildViewController(self)
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
		NotificationCenter.default.addObserver(self, selector: #selector(RootViewController.windowWillClose(_:)), name: .NSWindowWillClose, object:view.window!)
		NotificationCenter.default.addObserver(self, selector: #selector(RootViewController.receivedImportNotification(_:)), name: .FilesImported, object: nil)
		//create dimming view
		dimmingView = DimmingView(frame: view.bounds)
		view.addSubview(dimmingView!)
		(view as? RootView)?.dimmingView = dimmingView //required to block clicks to subviews
		//we have to wait until next time through event loop to set first responder
		self.performSelector(onMainThread: #selector(RootViewController.setupResponder), with: nil, waitUntilDone: false)

	}
	
	func windowWillClose(_ note: Notification) {
		if sessionOptional?.connectionOpen ?? false && (note.object as? NSWindow == view.window) {
			sessionController?.close()
			sessionController = nil
		}
	}
	
	// swiftlint:disable:next cyclomatic_complexity
	override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		guard let action = menuItem.action else { return false }
		switch action {
		case Selector.promptToImport, #selector(editFile(_:)):
			return fileHandler!.validateMenuItem(menuItem)
		case Selector.showFonts:
			if let fontHandler = currentFontUser(view.window?.firstResponder) {
				guard fontHandler.fontsEnabled() else { return false }
				updateFontFaceMenu(menuItem.submenu!, fontUser:fontHandler)
				return true
			}
			return false
		case Selector.showFontSizes:
			if let fontHandler = currentFontUser(view.window?.firstResponder) {
				guard fontHandler.fontsEnabled() else { return false }
				updateFontSizeMenu(menuItem.submenu!, fontUser:fontHandler)
				return true
			}
			return false
		case Selector.adjustFontSize:
			return true
		case Selector.runQuery, Selector.sourceQuery:
			return editor?.validateMenuItem(menuItem) ?? false
		case Selector.switchOutputTab, Selector.switchSidebarTab:
			return splitController?.validateMenuItem(menuItem) ?? false
		default:
			return false
		}
	}

	func setupResponder() {
		view.window?.makeFirstResponder(outputHandler?.initialFirstResponder())
	}
	
	func handlesToolbarItem(_ item: NSToolbarItem) -> Bool {
		if item.itemIdentifier == "search" {
			searchButton = item.view as? NSSegmentedControl
			TargetActionBlock { [weak self] sender in
				self?.toggleSearch(sender)
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
	
	/// selects the first file imported if it is a source file
	func receivedImportNotification(_ note: Notification) {
		guard let importer = note.object as? FileImporter else { return }
		guard let file = importer.importedFiles.first, file.fileType.isSourceFile else { return }
		os_log("selecting imported file", log: .app, type: .info)
		fileHandler?.selectedFile = importer.importedFiles.first
	}
	
	private func adjustDimmingView(hide: Bool) {
		precondition(appStatus != nil)
		guard self.dimmingView?.isHidden != hide else { return }
		self.dimmingView?.isHidden = hide
		if hide {
			self.formerFirstResponder = self.view.window?.firstResponder
			self.view.window?.makeFirstResponder(dimmingView)
		} else {
			self.view.window?.makeFirstResponder(self.formerFirstResponder)
		}
	}
	
	override func appStatusChanged() {
		progressDisposable = appStatus?.progressSignal.observe(on: UIScheduler()).observeValues
		{ [weak self] progressUpdate in
			switch progressUpdate.stage {
			case .start:
				self?.adjustDimmingView(hide: !progressUpdate.disableInput)
			case .completed, .failed:
				self?.adjustDimmingView(hide: true)
			case .value:
				break
			}
		}
	}
}

// MARK: - actions
extension RootViewController {
	@IBAction func toggleSearch(_ sender: Any?) {
		if responderChainContains(editor!)  {
			editor?.performTextFinderAction(sender)
		} else if let outputHandler = outputHandler {
			outputHandler.searchBarVisible = !outputHandler.searchBarVisible
		}
	}
	
	@IBAction override func performTextFinderAction(_ sender: Any?) {
		guard let item = sender as? NSValidatedUserInterfaceItem, let tag = NSTextFinderAction(rawValue: item.tag) else { return }
		if responderChainContains(editor)  {
			editor?.performTextFinderAction(sender)
		} else if responderChainContains(outputHandler as? NSResponder) {
			outputHandler?.handleSearch(action: tag)
		}
	}
	
	@IBAction func clearFileCache(_ sender: AnyObject?) {
		sessionController?.clearFileCache()
	}
	
	@IBAction func promptToImportFiles(_ sender: AnyObject?) {
		fileHandler?.promptToImportFiles(sender)
	}
	
	@IBAction func editFile(_ sender: Any) {
		fileHandler?.editFile(sender)
	}
	
	@IBAction func runQuery(_ sender: AnyObject?) {
		editor?.runQuery(sender)
	}
	
	@IBAction func sourceQuery(_ sender: AnyObject?) {
		editor?.sourceQuery(sender)
	}
	
	@IBAction func switchSidebarTab(_ sender: NSMenuItem?) {
		splitController?.switchSidebarTab(sender)
	}

	@IBAction func switchOutputTab(_ sender: NSMenuItem?) {
		splitController?.switchOutputTab(sender)
	}
}

// MARK: - fonts
extension RootViewController: ManageFontMenu {
	@IBAction func showFonts(_ sender: AnyObject?) {
		//do nothing, just a place holder for menu validation
	}
	
	@IBAction func showFontSizes(_ sender: AnyObject?) {
		//do nothing. just placeholder for menu validation
	}
	
	@IBAction func adjustFontSize(_ sender: NSMenuItem) {
		var fsize = sender.tag
		if fsize >= 9 {
			let fontUser = currentFontUser(view.window!.firstResponder)
			fontUser?.currentFontDescriptor = fontUser!.currentFontDescriptor.withSize(CGFloat(fsize))
			return
		}
		//prompt for size to use
		let sboard = NSStoryboard(name: "Main", bundle: nil)
		guard let wc = sboard.instantiateController(withIdentifier: "FontSizeWindowController") as? NSWindowController, let vc = wc.contentViewController as? SingleInputViewController else
		{
			fatalError()
		}
		vc.saveAction = { inputVC in
			fsize = inputVC.textField!.integerValue
			if fsize >= 9 && fsize <= 64 {
				let fontUser = currentFontUser(self.view.window!.firstResponder)
				fontUser?.currentFontDescriptor = fontUser!.currentFontDescriptor.withSize(CGFloat(fsize))
			}
			print("size = \(inputVC.textField?.intValue ?? -1)")
		}
		vc.enableSaveButton = { val in
			guard let ival = val as? Int else { return false }
			return ival >= 9 && ival <= 64
		}
		vc.textField!.objectValue = currentFontUser(view.window!.firstResponder)?.currentFontDescriptor.pointSize
		presentViewControllerAsSheet(vc)
	}
	
	func updateFontFaceMenu(_ menu: NSMenu, fontUser: UsesAdjustableFont) {
		menu.removeAllItems()
		//we want regular weight monospaced fonts
		let traits = [NSFontSymbolicTrait: NSFontMonoSpaceTrait, NSFontWeightTrait: 0]
		let attrs = [NSFontTraitsAttribute: traits]
		let filterDesc = NSFontDescriptor(fontAttributes: attrs)
		//get matching fonts and sort them by name
		let fonts = filterDesc.matchingFontDescriptors(withMandatoryKeys: nil).sorted {
			// swiftlint:disable:next force_cast
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

	func updateFontSizeMenu(_ menu: NSMenu, fontUser: UsesAdjustableFont) {
		var markedCurrent = false
		var customItem: NSMenuItem?
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

// MARK: - SessionControllerDelegate
extension RootViewController: SessionControllerDelegate {
	func sessionClosed() {
		self.sessionClosedHandler?()
	}
	
	func filesRefreshed() {
		fileHandler?.filesRefreshed(nil)
	}

	func saveState() -> JSON {
		var dict = [String: JSON]()
		dict["editor"] = editor!.saveState()
		dict["selFile"] = .int(fileHandler?.selectedFile?.fileId ?? -1)
		return .dictionary(dict)
	}
	
	func restoreState(_ state: JSON) {
		if let editorState = state["editor"] {
			editor?.restoreState(editorState)
		}
		if let fileId = try? state.getInt(at: "selFile"), fileId > 0, let file = session.workspace.file(withId: fileId) {
			fileHandler?.selectedFile = file
		}
	}
}

// MARK: - FileViewControllerDelegate
extension RootViewController: FileViewControllerDelegate {
	func fileSelectionChanged(_ file: File?, forEditing: Bool) {
		if nil == file {
			self.editor?.fileSelectionChanged(nil)
			self.outputHandler?.showFile(nil)
		} else if file!.fileType.isSourceFile || (forEditing && file!.fileSize <= MaxEditableFileSize) {
			self.editor?.fileSelectionChanged(file)
		} else {
			outputHandler?.showFile(file)
//			if let editingFile = editor?.currentDocument?.file {
//				fileHandler?.selectedFile = editingFile
//			}
		}
	}
}

// MARK: -
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
	var dimmingView: DimmingView?
	//if dimmingView is visible, block all subviews from getting clicks
	override func hitTest(_ aPoint: NSPoint) -> NSView? {
		if dimmingView != nil && !dimmingView!.isHidden {
			return self
		}
		return super.hitTest(aPoint)
	}
}
