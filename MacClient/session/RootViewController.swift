//
//  RootViewController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import MJLLogger
import ReactiveSwift
import Networking
import Model

let MaxEditableFileSize: Int = 1024 * 1024 // 1 MB

class RootViewController: AbstractSessionViewController
{
	// MARK: - properties
	var sessionController: SessionController?

	var statusTimer: Timer?
	var sessionClosedHandler: (() -> Void)?

	fileprivate var progressDisposable: Disposable?
	fileprivate var dimmingView: DimmingView?
	weak var splitController: SessionSplitController?
	weak var outputHandler: OutputHandler?
	weak var fileHandler: SidebarFileController?
	weak var editorController: RootEditorController?
	var formerFirstResponder: NSResponder? //used to restore first responder when dimmingview goes away

	deinit {
		sessionController?.close()
	}

	override func sessionChanged() {
		let variableHandler: VariableHandler = firstChildViewController(self)!
		editorController = firstChildViewController(self)!
		sessionController = SessionController(session: session, delegate: self, editor: editorController!, outputHandler: outputHandler!, variableHandler: variableHandler)
		outputHandler?.sessionController = sessionController
		sessionController?.appStatus = appStatus
		// link up the preview editor/output controllers
		editorController?.previewEditor.outputController = outputHandler?.previewOutputController
	}

	// MARK: - Lifecycle
	override func viewWillAppear() {
		super.viewWillAppear()
		guard splitController == nil else { return } //only run once
		splitController = firstChildViewController(self)
		outputHandler = firstChildViewController(self)
		fileHandler = firstChildViewController(self)
		fileHandler?.delegate = self
	}

	override func viewDidAppear() {
		super.viewDidAppear()
		NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose(_:)), name: NSWindow.willCloseNotification, object: view.window!)
		NotificationCenter.default.addObserver(self, selector: #selector(receivedImportNotification(_:)), name: .filesImported, object: nil)
		//create dimming view
		dimmingView = DimmingView(frame: view.bounds)
		view.addSubview(dimmingView!)
		(view as? RootView)?.dimmingView = dimmingView //required to block clicks to subviews
		//we have to wait until next time through event loop to set first responder
		self.performSelector(onMainThread: #selector(setupResponder), with: nil, waitUntilDone: false)
	}

	@objc func windowWillClose(_ note: Notification) {
		if sessionOptional?.connectionOpen ?? false && (note.object as? NSWindow == view.window) {
			sessionController?.close()
			sessionController = nil
		}
	}

	// swiftlint:disable:next cyclomatic_complexity
	@objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		guard let action = menuItem.action else { return false }
		switch action {
		case #selector(promptToImportFiles(_:)), #selector(editFile(_:)):
			return fileHandler!.validateMenuItem(menuItem)
		case #selector(exportSelectedFile(_:)):
			return fileHandler!.selectedFile != nil
		case #selector(exportZippedFiles(_:)), #selector(exportAllFiles(_:)):
			return session.workspace.files.count > 0
		case Selector.showFonts:
			if let fontHandler = currentFontUser(view.window?.firstResponder) {
				guard fontHandler.fontsEnabled() else { return false }
				updateFontFaceMenu(menuItem.submenu!, fontUser: fontHandler)
				return true
			}
			return false
		case Selector.showFontSizes:
			if let fontHandler = currentFontUser(view.window?.firstResponder) {
				guard fontHandler.fontsEnabled() else { return false }
				updateFontSizeMenu(menuItem.submenu!, fontUser: fontHandler)
				return true
			}
			return false
		case Selector.adjustFontSize:
			return true
		case Selector.runQuery, Selector.sourceQuery:
			return sessionController?.codeEditor.canExecute ?? false
		case #selector(updatePreview(_:)):
			return editorController!.currentEditorMode == .preview
		case #selector(switchOutputTab(_:)), #selector(switchSidebarTab(_:)):
			return splitController?.validateMenuItem(menuItem) ?? false
		case #selector(clearConsole(_:)), #selector(clearImageCache(_:)), #selector(exportAllFiles(_:)):
			return true
		case #selector(switchToSourceMode(_:)):
			return sessionController?.codeEditor.canSwitchToSourceMode ?? false
		default:
			return false
		}
	}

	@objc func setupResponder() {
		view.window?.makeFirstResponder(outputHandler?.initialFirstResponder())
	}

	/// selects the first file imported if it is a source file
	@objc func receivedImportNotification(_ note: Notification) {
		guard let importer = note.object as? FileImporter else { return }
		sessionOptional?.workspace.whenFilesExist(withIds: importer.importedFileIds, within: 1.0)
			.startWithResult { result in
			guard case .success(let files) = result else { return }
			guard let file = files.first(where: { $0.fileType.isSource }) else { return }
			Log.info("selecting imported file", .app)
			self.fileHandler?.selectedFile = file
		}
	}

	private func adjustDimmingView(hide: Bool) {
		Log.info("adjustDimmingView: \(hide)", .app)
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

	// when the status changes, we show/hide the dimming view to disable interaction
	override func appStatusChanged() {
		progressDisposable = appStatus?.progressSignal.observe(on: UIScheduler()).observeValues
		{ [weak self] progressUpdate in
			Log.debug("appStatusChanged \(progressUpdate.stage)", .app)
			switch progressUpdate.stage {
			case .start:
				self?.adjustDimmingView(hide: !progressUpdate.disableInput)
			case .completed, .failed:
				self?.adjustDimmingView(hide: true)
			case .value:
				break
			}
		}
		sessionController?.appStatus = appStatus
	}
}

// MARK: - actions
extension RootViewController {
	@IBAction func clearFileCache(_ sender: Any?) {
		sessionController?.clearFileCache()
	}

	@IBAction func clearImageCache(_ sender: Any?) {
		sessionController?.clearImageCache()
	}

	@IBAction func clearConsole(_ sender: Any?) {
		outputHandler?.clearConsole(sender)
	}

	@IBAction func promptToImportFiles(_ sender: Any?) {
		fileHandler?.promptToImportFiles(sender)
	}

	@IBAction func exportSelectedFile(_ sender: Any?) {
		fileHandler?.exportSelectedFile(sender)
	}

	@IBAction func exportZippedFiles(_ sender: Any?) {
		fileHandler?.exportZippedFiles(sender)
	}

	@IBAction func exportAllFiles(_ sender: Any?) {
		fileHandler?.exportAllFiles(sender)
	}

	@IBAction func editFile(_ sender: Any) {
		fileHandler?.editFile(sender)
	}

	@IBAction func runQuery(_ sender: Any?) {
		sessionController?.codeEditor.executeSource(type: .run)
	}

	@IBAction func sourceQuery(_ sender: Any?) {
		sessionController?.codeEditor.executeSource(type: .source)
	}

	@IBAction func switchSidebarTab(_ sender: NSMenuItem?) {
		splitController?.switchSidebarTab(sender)
	}

	@IBAction func switchOutputTab(_ sender: NSMenuItem?) {
		splitController?.switchOutputTab(sender)
	}

	@IBAction func switchToPreviewMode(_ sender: Any?) {
		sessionController?.codeEditor.switchTo(mode: .preview)
	}

	@IBAction func switchToSourceMode(_ sender: Any?) {
		sessionController?.codeEditor.switchTo(mode: .source)
	}
	
	@IBAction func updatePreview(_ sender: Any?) {
		outputHandler?.switchToPreview()
		outputHandler?.previewOutputController?.updatePreview()
	}
}

// MARK: - fonts
extension RootViewController: ManageFontMenu {
	@IBAction func showFonts(_ sender: Any?) {
		//do nothing, just a place holder for menu validation
	}

	@IBAction func showFontSizes(_ sender: Any?) {
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
		let sboard = NSStoryboard(name: .mainBoard, bundle: nil)
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
		presentAsSheet(vc)
	}

	func updateFontFaceMenu(_ menu: NSMenu, fontUser: UsesAdjustableFont) {
		menu.removeAllItems()
		//we want regular weight monospaced fonts
		let traits = [NSFontDescriptor.TraitKey.symbolic: NSFontMonoSpaceTrait, .weight: 0]
		let attrs = [NSFontDescriptor.AttributeName.traits: traits]
		let filterDesc = NSFontDescriptor(fontAttributes: attrs)
		//get matching fonts and sort them by name
		let fonts = filterDesc.matchingFontDescriptors(withMandatoryKeys: nil).sorted {
			// swiftlint:disable:next force_cast
			($0.object(forKey: NSFontDescriptor.AttributeName.name) as! String).lowercased() < ($1.object(forKey: NSFontDescriptor.AttributeName.name) as! String).lowercased()
		}
		//now add menu items for them
		for aFont in fonts {
			let menuItem = NSMenuItem(title: aFont.visibleName, action: #selector(UsesAdjustableFont.fontChanged), keyEquivalent: "")
			menuItem.representedObject = aFont
			if fontUser.currentFontDescriptor.fontName == aFont.fontName {
				menuItem.state = .on
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
			anItem.state = .off
			if anItem.tag == curSize {
				anItem.state = .on
				markedCurrent = true
			} else if anItem.tag == 0 {
				customItem = anItem
			}
			anItem.isEnabled = true
		}
		if !markedCurrent {
			customItem?.state = .on
		}
	}
}

// MARK: - SessionControllerDelegate
extension RootViewController: SessionControllerDelegate {
	// need to inform user that the connection was closed, then inform our close handler (which is responsible for closing us)
	func sessionClosed(details: String?) {
		let strDetails = details ?? ""
		if let status = appStatus {
			status.presentAlert(session, message: NSLocalizedString("Connection Closed", comment: "title for connection closed alert"), details: strDetails) { _ in
				self.sessionClosedHandler?()
			}
		} else {
			self.sessionClosedHandler?()
		}
	}

	func filesRefreshed() {
		fileHandler?.filesRefreshed([])
	}

	func save(state: inout SessionState) {
		state.editorState.lastSelectedFileId = fileHandler?.selectedFile?.fileId ?? -1
		editorController?.save(state: &state.editorState)
	}

	func restore(state: SessionState) {
		editorController?.restore(state: state.editorState)
		if state.editorState.lastSelectedFileId > 0,
			let file = session.workspace.file(withId: state.editorState.lastSelectedFileId)
		{
			fileHandler?.selectedFile = file
		}
	}
}

// MARK: - FileViewControllerDelegate
extension RootViewController: FileViewControllerDelegate {
	func fileSelectionChanged(_ file: AppFile?, forEditing: Bool) {
		if nil == file {
			editorController?.fileChanged(file: nil)
			self.outputHandler?.show(file: nil)
		} else if file!.fileType.isSource || (forEditing && file!.fileSize <= MaxEditableFileSize) {
			editorController?.fileChanged(file: file) { success in
				guard success else { return }
				self.outputHandler?.considerTabChange(editorMode: self.editorController!.currentEditorMode)
			}
		} else {
			outputHandler?.show(file: file)
//			if let editingFile = editor?.currentDocument?.file {
//				fileHandler?.selectedFile = editingFile
//			}
		}
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
