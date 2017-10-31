//
//  SidebarFileController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import os
import ReactiveSwift
import Result
import SwiftyUserDefaults
import ClientCore
import Networking
import Model

// swiftlint:disable file_length type_body_length

///selectors used in this file, aliased with shorter, descriptive names
private extension Selector {
	static let editFile = #selector(SidebarFileController.editFile(_:))
	static let addDocument = #selector(SidebarFileController.addDocumentOfType(_:))
	static let addFileMenu =  #selector(SidebarFileController.addFileMenuAction(_:))
	static let exportSelectedFile = #selector(SidebarFileController.exportSelectedFile(_:))
	static let exportAll = #selector(SidebarFileController.exportAllFiles(_:))
}

class FileRowData: Equatable {
	var sectionName: String?
	var file: AppFile?
	init(name: String?, file: AppFile?) {
		self.sectionName = name
		self.file = file
	}
	static public func == (lhs: FileRowData, rhs: FileRowData) -> Bool {
		if lhs.sectionName != nil && lhs.sectionName == rhs.sectionName { return true }
		if rhs.file != nil && lhs.file != nil && lhs.file?.fileId == rhs.file?.fileId { return true }
		return false
	}
}

protocol FileViewControllerDelegate: class {
	func fileSelectionChanged(_ file: AppFile?, forEditing: Bool)
}

let FileDragTypes = [NSPasteboard.PasteboardType(kUTTypeFileURL as String)]

let addFileSegmentIndex: Int = 0
let removeFileSegmentIndex: Int = 1

class SidebarFileController: AbstractSessionViewController, NSTableViewDataSource, NSTableViewDelegate, NSOpenSavePanelDelegate, NSMenuDelegate
{
	// MARK: properties
	let sectionNames: [String] = ["Source Files", "Images", "Other"]

	@IBOutlet var tableView: NSTableView!
	@IBOutlet var addRemoveButtons: NSSegmentedControl?
	@IBOutlet var messageView: NSView?
	@IBOutlet var messageLabel: NSTextField?
	@IBOutlet var messageButtons: NSStackView?
	
	var rowData: [FileRowData] = [FileRowData]()
	weak var delegate: FileViewControllerDelegate?
	lazy var importPrompter: MacFileImportSetup? = { MacFileImportSetup() }()
	var fileImporter: FileImporter?
	private var fileChangeDisposable: Disposable?
	/// used to disable interface when window is busy
	private var busyDisposable: Disposable?
	fileprivate var selectionChangeInProgress = false
	fileprivate var formatMenu: NSMenu?
	
	var selectedFile: AppFile? { didSet { fileSelectionChanged() } }

	deinit {
		NotificationCenter.default.removeObserver(self)
	}
	
	// MARK: - lifecycle
	override func awakeFromNib() {
		super.awakeFromNib()

		if addRemoveButtons != nil {
			let menu = NSMenu(title: "new document format")
			for (index, aType) in FileType.creatableFileTypes.enumerated() {
				let mi = NSMenuItem(title: aType.details ?? "unknown", action: .addDocument, keyEquivalent: "")
				mi.representedObject = index
				menu.addItem(mi)
			}
			menu.autoenablesItems = false
			//NOTE: the action method of the menu item wasn't being called the first time. This works all times.
			NotificationCenter.default.addObserver(self, selector: .addFileMenu, name: NSMenu.didSendActionNotification, object: menu)
			addRemoveButtons?.setMenu(menu, forSegment: 0)
			addRemoveButtons?.target = self
			formatMenu = menu
		}
		if tableView != nil {
			tableView.setDraggingSourceOperationMask(.copy, forLocal: true)
			tableView.setDraggingSourceOperationMask(.copy, forLocal: false)
			tableView.draggingDestinationFeedbackStyle = .none
			tableView.registerForDraggedTypes(FileDragTypes)
		}
		adjustForFileSelectionChange()
	}
	
	override func sessionChanged() {
		fileChangeDisposable?.dispose()
		fileChangeDisposable = session.workspace.fileChangeSignal.observeValues(filesRefreshed)
		loadData()
		tableView.reloadData()
		if selectedFile != nil {
			fileSelectionChanged()
		}
		if rowData.count == 0 {
			messageView?.isHidden = false
		} else {
			messageView?.isHidden = true
		}
	}
	
	override func appStatusChanged() {
		busyDisposable = appStatus?.busySignal.observe(on: UIScheduler()).observeValues { [weak self] isBusy in
			guard let tv = self?.tableView else { return }
			if isBusy {
				tv.unregisterDraggedTypes()
			} else {
				tv.registerForDraggedTypes(FileDragTypes)
			}
		}
	}
	
	func loadData() {
		var sectionedFiles = [[AppFile](), [AppFile](), [AppFile]()]
		for aFile in session.workspace.files.sorted(by: { $1.name > $0.name }) {
			if aFile.fileType.isSource {
				sectionedFiles[0].append(aFile)
			} else if aFile.fileType.isImage {
				sectionedFiles[1].append(aFile)
			} else {
				sectionedFiles[2].append(aFile)
			}
		}
		rowData.removeAll()
		for i in 0..<sectionNames.count where sectionedFiles[i].count > 0 {
			rowData.append(FileRowData(name: sectionNames[i], file: nil))
			rowData.append(contentsOf: sectionedFiles[i].map({ return FileRowData(name:nil, file:$0) }))
		}
	}
	
	fileprivate func adjustForFileSelectionChange() {
		addRemoveButtons?.setEnabled(selectedFile != nil, forSegment: removeFileSegmentIndex)
	}
	
	override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		guard let action = menuItem.action else {
			return super.validateMenuItem(menuItem)
		}
		switch action {
			case Selector.editFile:
				let fileName = selectedFile?.name ?? ""
				menuItem.title = String.localizedStringWithFormat(NSLocalizedString("Edit File", comment: ""), fileName)
				guard let file = selectedFile, file.fileSize <= MaxEditableFileSize else { return false }
				return file.fileType.isEditable
			case Selector.promptToImport:
				return true
			case Selector.exportSelectedFile:
				return selectedFile != nil
			case Selector.exportAll:
				return true
			default:
				return super.validateMenuItem(menuItem)
		}
	}
	
	//as the delegate for the action menu, need to enable/disable items
	func menuNeedsUpdate(_ menu: NSMenu) {
		menu.items.forEach { item in
			guard let action = item.action else { return }
			switch action {
			case Selector.promptToImport:
				item.isEnabled = true
			case Selector.editFile:
				item.isEnabled = selectedFile != nil && selectedFile!.fileSize <= MaxEditableFileSize
			default:
				item.isEnabled = selectedFile != nil
			}
		}
	}
	
	func fileDataIndex(fileId: Int) -> Int? {
		for (idx, data) in rowData.enumerated() where data.file?.fileId == fileId {
			return idx
		}
		return nil
	}
	
	// NSMenu calls this method before an item's action is called. we listen to it from the add button's menu
	@objc func addFileMenuAction(_ note: Notification) {
		guard let menuItem = note.userInfo?["MenuItem"] as? NSMenuItem,
			let index = menuItem.representedObject as? Int
			else { return }
		let fileType = FileType.creatableFileTypes[index]
		let prompt = NSLocalizedString("Filename:", comment: "")
		let baseName = NSLocalizedString("Untitled", comment: "default file name")
		DispatchQueue.main.async {
			self.promptForFilename(prompt: prompt, baseName: baseName, type: fileType) { (name) in
				guard let newName = name else { return }
				//TODO: implement new file templates
				self.session.create(fileName: newName, contentUrl: nil) { result in
					// the id of the file that was created
					guard let fid = result.value else {
						self.logMessage("error creating empty file: %{public}@", result.error!.localizedDescription)
						self.appStatus?.presentError(result.error!, session: self.session)
						return
					}
					self.select(fileId: fid)
				}
			}
		}
	}
	
	// MARK: - actions
	@IBAction func createFirstFile(_ sender: Any?) {
		guard let button = sender as? NSButton else { return }
		DispatchQueue.main.async {
			switch button.tag {
			case 0: self.promptToImportFiles(sender)
			case 1:
				self.formatMenu?.popUp(positioning: nil, at: NSPoint.zero, in: self.messageButtons)
			default: break
			}
			//            NSAnimationContext.runAnimationGroup({ (context) in
			//                context.allowsImplicitAnimation = true
			self.messageView?.animator().isHidden = true
			//            }, completionHandler: nil)
		}
		//        messageView?.isHidden = true
	}
	
	@IBAction func deleteFile(_ sender: AnyObject?) {
		guard let file = selectedFile else {
			logMessage("deleteFile should never be called without selected file")
			return
		}
		let defaults = UserDefaults.standard
		if defaults[.suppressDeleteFileWarnings] {
			self.actuallyPerformDelete(file: file)
			return
		}
		confirmAction(message: NSLocalizedString(LocalStrings.deleteFileWarning, comment: ""),
					  infoText: String(format: NSLocalizedString(LocalStrings.deleteFileWarningInfo, comment: ""), file.name),
					  buttonTitle: NSLocalizedString("Delete", comment: ""),
					  defaultToCancel: true,
					  suppressionKey: .suppressDeleteFileWarnings)
		{ (confirmed) in
			guard confirmed else { return }
			self.actuallyPerformDelete(file: file)
		}
	}
	
	@IBAction func duplicateFile(_ sender: AnyObject?) {
		guard let file = selectedFile else {
			logMessage("duplicateFile should never be called without selected file")
			return
		}
		let prompt = NSLocalizedString("Filename:", comment: "")
		let baseName = NSLocalizedString("Untitled", comment: "default file name")
		DispatchQueue.main.async {
			self.promptForFilename(prompt: prompt, baseName: baseName, type: file.fileType) { (name) in
				guard let newName = name else { return }
				self.session.duplicate(file: file, to: newName)
					.updateProgress(status: self.appStatus!, actionName: "Duplicate \(file.name)")
					.startWithResult { result in
					// the id of the file that was created
					guard let fid = result.value else {
						self.logMessage("error duplicating file: %{public}@", result.error!.localizedDescription)
						self.appStatus?.presentError(result.error!, session: self.session)
						return
					}
					self.select(fileId: fid)
				}
			}
		}
	}

	@IBAction func renameFile(_ sender: AnyObject?) {
		guard let cellView = tableView.view(atColumn: 0, row: tableView.selectedRow, makeIfNecessary: false) as? EditableTableCellView else
		{
			logMessage("renameFile: failed to get tableViewCell")
			return
		}
		guard let file = cellView.objectValue as? AppFile else {
			logMessage("renameFile: no file for file cell view", type: .error)
			return
		}
		cellView.validator = { self.validateRename(file: file, newName: $0) }
		cellView.textField?.isEditable = true
		tableView.editColumn(0, row: tableView.selectedRow, with: nil, select: true)
		cellView.editText { value in
			cellView.textField?.isEditable = false
			cellView.textField?.stringValue = file.name
			guard var name = value else { return }
			if !name.hasSuffix(".\(file.fileType.fileExtension)") {
				name += ".\(file.fileType.fileExtension)"
			}
			self.session.rename(file: file, to: name)
				.updateProgress(status: self.appStatus!, actionName: "Rename \(file.name)")
				.startWithResult { result in
				guard let error = result.error else {
					self.select(fileId: file.fileId)
					return
				}
				self.logMessage("error duplicating file: %{public}@", error.localizedDescription)
				self.appStatus?.presentError(error, session: self.session)
			}
		}
	}
	
	@IBAction func editFile(_ sender: Any) {
		delegate?.fileSelectionChanged(selectedFile, forEditing: true)
	}
	
	// never gets called, but file type menu items must have an action or addFileMenuAction never gets called
	@IBAction func addDocumentOfType(_ menuItem: NSMenuItem) {
	}
	
	@IBAction func segButtonClicked(_ sender: AnyObject?) {
		switch addRemoveButtons!.selectedSegment {
			case addFileSegmentIndex:
				//should never be called since a menu is attached
				assertionFailure("segButtonClicked should never be called for addSegment")
			case removeFileSegmentIndex:
				deleteFile(sender)
			default:
				assertionFailure("unknown segment selected")
		}
	}

	@IBAction func promptToImportFiles(_ sender:Any?) {
		if nil == importPrompter {
			importPrompter = MacFileImportSetup()
		}
		importPrompter!.performFileImport(view.window!, workspace: session.workspace) { files in
			guard files != nil else { return } //user canceled import
			self.importFiles(files!)
		}
	}

	@IBAction func exportSelectedFile(_ sender: AnyObject?) {
		let defaults = UserDefaults.standard
		let savePanel = NSSavePanel()
		savePanel.isExtensionHidden = false
		savePanel.allowedFileTypes = [(selectedFile?.fileType.fileExtension)!]
		savePanel.nameFieldStringValue = (selectedFile?.name)!
		if let bmarkData = defaults[.lastExportDirectory] {
			do {
				savePanel.directoryURL = try (NSURL(resolvingBookmarkData: bmarkData, options: [], relativeTo: nil, bookmarkDataIsStale: nil) as URL)
			} catch {
			}
		}
		savePanel.beginSheetModal(for: view.window!) { result in
			do {
				let bmark = try (savePanel.directoryURL as NSURL?)?.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
				defaults[.lastExportDirectory] = bmark
			} catch let err as NSError {
				os_log("why did we get error creating export bookmark: %{public}@", log: .app, type: .error, err)
			}
			savePanel.close()
			if result == .OK && savePanel.url != nil {
				do {
					try Foundation.FileManager.default.copyItem(at: self.session.fileCache.cachedUrl(file:self.selectedFile!), to: savePanel.url!)
				} catch let error as NSError {
					os_log("failed to copy file for export: %{public}@", log: .app, type: .error, error)
					let alert = NSAlert(error:error)
					alert.beginSheetModal(for: self.view.window!, completionHandler: { (_) -> Void in
						//do nothing
					})
				}
			}
		}
	}
	
	@IBAction func exportAllFiles(_ sender: AnyObject?) {
		//TODO: implement
	}
	
	// MARK: - private methods

	/// wrapper around os_log
	fileprivate func logMessage(_ message: StaticString, type: OSLogType = .default, _ args: CVarArg...) {
		os_log(message, log: .app, type: type, args)
	}
	
	fileprivate func select(fileId: Int) {
		// the id of the file that was created
		guard let fidx = self.fileDataIndex(fileId: fileId) else {
			logMessage("selecting unknown file %d", fileId)
			return
		}
		tableView.selectRowIndexes(IndexSet(integer: fidx), byExtendingSelection: false)
	}

	fileprivate func actuallyPerformDelete(file: AppFile) {
		self.session.remove(file: file)
			.updateProgress(status: self.appStatus!, actionName: "Delete \(file.name)")
			.startWithResult { result in
				DispatchQueue.main.async {
					if let error = result.error {
						self.appStatus?.presentError(error, session: self.session)
					} else {
						self.delegate?.fileSelectionChanged(nil, forEditing: false)
					}
				}
		}
	}
	
	/// prompts for a filename
	///
	/// - Parameters:
	///   - prompt: label shown to user
	///   - baseName: base file name (without extension)
	///   - type: the type of file being prompted for
	///   - handler: called when complete. If value is nil, the user canceled the prompt
	private func promptForFilename(prompt: String, baseName: String, type: FileType, handler: @escaping (String?) -> Void)
	{
		let fileExtension = ".\(type.fileExtension)"
		let prompter = InputPrompter(prompt: prompt, defaultValue: baseName + fileExtension, suffix: fileExtension)
		prompter.minimumStringLength = type.fileExtension.count + 1
		let fileNames = session.workspace.files.map { return $0.name }
		prompter.validator = { (proposedName) in
			return fileNames.filter({ $0.caseInsensitiveCompare(proposedName) == .orderedSame }).count == 0
		}
		prompter.prompt(window: self.view.window!) { (gotValue, value) in
			guard gotValue, var value = value else { handler(nil); return }
			if !value.hasSuffix(fileExtension) {
				value += fileExtension
			}
			handler(value)
		}
	}
	
	private func validateRename(file: AppFile, newName: String?) -> Bool {
		guard var name = newName else { return true } //empty is allowable
		if !name.hasSuffix(".\(file.fileType.fileExtension)") {
			name += ".\(file.fileType.fileExtension)"
		}
		guard name.count > 3 else { return false }
		//if same name, is valid
		guard name.caseInsensitiveCompare(file.name) != .orderedSame else { return true }
		//no duplicate names
		let fileNames = session.workspace.files.map { return $0.name }
		guard fileNames.filter({ $0.caseInsensitiveCompare(name) == .orderedSame }).count == 0 else { return false }
		return true
	}
	
	private func importFiles(_ files: [FileImporter.FileToImport]) {
		let converter = { (iprogress: FileImporter.ImportProgress) -> ProgressUpdate? in
			return ProgressUpdate(.value, message: iprogress.status, value: iprogress.percentComplete)
		}
		do {
			fileImporter = try FileImporter(files, fileCache: self.session.fileCache, connectInfo: session.conInfo)
		} catch {
			let myError = Rc2Error(type: .file, nested: error)
			appStatus?.presentError(myError, session: session)
			return
		}
		//save reference so ARC doesn't dealloc importer
		fileImporter!.producer()
			.updateProgress(status: appStatus!, actionName: "Import", determinate: true, converter: converter)
			.start
			{ [weak self] event in
				switch event {
				case .failed(let error):
					os_log("got import error %{public}@", log: .app, type: .error, error.localizedDescription)
					self?.fileImporter = nil //free up importer
				case .completed:
					NotificationCenter.default.post(name: .FilesImported, object: self?.fileImporter!)
					self?.fileImporter = nil //free up importer
				case .interrupted:
					os_log("import canceled", log: .app)
					self?.fileImporter = nil //free up importer
				default:
					break
				}
			}
	}

	// MARK: - TableView datasource/delegate implementation
	func numberOfRows(in tableView: NSTableView) -> Int {
		return rowData.count
	}
	
	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		let data = rowData[row]
		if data.sectionName != nil {
			// swiftlint:disable:next force_cast
			let tview = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "string"), owner: nil) as! NSTableCellView
			tview.textField!.stringValue = data.sectionName!
			return tview
		} else {
			// swiftlint:disable:next force_cast
			let fview = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "file"), owner: nil) as! EditableTableCellView
			fview.objectValue = data.file
			fview.textField?.stringValue = data.file!.name
			return fview
		}
	}
	
	func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
		return rowData[row].sectionName != nil
	}
	
	func tableViewSelectionDidChange(_ notification: Notification) {
		if tableView.selectedRow >= 0 {
			selectedFile = rowData[tableView.selectedRow].file
		} else {
			selectedFile = nil
		}
		adjustForFileSelectionChange()
		delegate?.fileSelectionChanged(selectedFile, forEditing: false)
	}
	
	func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
		return rowData[row].file != nil
	}
	
	func tableView(_ tableView: NSTableView, writeRowsWith rowIndexes: IndexSet, to pboard: NSPasteboard) -> Bool {
		guard let row = rowIndexes.last, let file = rowData[row].file else { return false }
		let url = session.fileCache.cachedUrl(file: file) as NSURL
		pboard.declareTypes(url.writableTypes(for: pboard), owner: nil)
		url.write(to: pboard)
		return true
	}
	
	func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation
	{
		return importPrompter!.validateTableViewDrop(info)
	}

	func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool
	{
		importPrompter!.acceptTableViewDrop(info, workspace: session.workspace, window: view.window!) { (files) in
			self.importFiles(files)
		}
		return true
	}
}

// MARK: - FileHandler implementation
extension SidebarFileController: FileHandler {
	func filesRefreshed(_ changes: [AppWorkspace.FileChange]) {
		//TODO: ideally should figure out what file was changed and animate the tableview update instead of refreshing all rows
		//TODO: updated file always shows last, which is wrong
		loadData()
		//preserve selection
		let selFile = selectedFile
		tableView.reloadData()
		if selFile != nil, let idx = rowData.index(where: { $0.file?.fileId ?? -1 == selFile!.fileId }) {
			tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
		}
	}
	
	func fileSelectionChanged() {
		guard !selectionChangeInProgress else { return }
		selectionChangeInProgress = true
		defer { selectionChangeInProgress = false }
		guard let file = selectedFile else {
			DispatchQueue.main.async {
				self.tableView.selectRowIndexes(IndexSet(), byExtendingSelection: false)
			}
			return
		}
		guard let idx = fileDataIndex(fileId: file.fileId) else {
			os_log("failed to find file to select", log: .app, type: .info)
			return
		}
		DispatchQueue.main.async {
			self.tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
		}
	}
}

// MARK: - Accessory Classes
//least hackish way to get segment's menu to show immediately if set, otherwise perform control's action
class AddRemoveSegmentedCell: NSSegmentedCell {
	override var action: Selector? {
		get {
			if self.menu(forSegment: self.selectedSegment) != nil { return nil }
			return super.action!
		}
		set { super.action = newValue }
	}
}

class FileTableView: NSTableView {
	override func menu(for event: NSEvent) -> NSMenu? {
		let row = self.row(at: convert(event.locationInWindow, from: nil))
		if row != -1 { //if right click is over a row, select that row
			selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
		}
		return super.menu(for: event)
	}
}
