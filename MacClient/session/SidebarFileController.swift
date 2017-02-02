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
import NotifyingCollection
import ClientCore
import Networking

// MARK: Keys for UserDefaults
extension DefaultsKeys {
	static let lastExportDirectory = DefaultsKey<Data?>("rc2.LastExportDirectory")
	static let supressDeleteFileWarnings = DefaultsKey<Bool>("SupressDeleteFileWarning")
}

///selectors used in this file, aliased with shorter, descriptive names
private extension Selector {
	static let addDocument = #selector(SidebarFileController.addDocumentOfType(_:))
	static let addFileMenu =  #selector(SidebarFileController.addFileMenuAction(_:))
	static let exportSelectedFile = #selector(SidebarFileController.exportSelectedFile(_:))
	static let exportAll = #selector(SidebarFileController.exportAllFiles(_:))
}

class FileRowData: Equatable {
	var sectionName: String?
	var file: File?
	init(name: String?, file: File?) {
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
	func fileSelectionChanged(_ file: File?)
}

let FileDragTypes = [kUTTypeFileURL as String]

let addFileSegmentIndex: Int = 0
let removeFileSegmentIndex: Int = 1

//TODO: make sure when delegate renames file our list gets updated

class SidebarFileController: AbstractSessionViewController, NSTableViewDataSource, NSTableViewDelegate, FileHandler, NSOpenSavePanelDelegate, NSMenuDelegate
{
	//MARK: properties
	let sectionNames: [String] = ["Source Files", "Images", "Other"]

	@IBOutlet var tableView: NSTableView!
	@IBOutlet var addRemoveButtons: NSSegmentedControl?
	var rowData: [FileRowData] = [FileRowData]()
	var delegate: FileViewControllerDelegate?
	lazy var importPrompter: MacFileImportSetup? = { MacFileImportSetup() }()
	var fileImporter: FileImporter?
	private var fileChangeDisposable: Disposable?
	private var busyDisposable: Disposable?
	
	var selectedFile:File? {
		guard tableView.selectedRow >= 0 else { return nil }
		return rowData[tableView.selectedRow].file
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
	}
	
	//MARK: - lifecycle
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
			NotificationCenter.default.addObserver(self, selector: .addFileMenu, name: NSNotification.Name.NSMenuDidSendAction, object: menu)
			addRemoveButtons?.setMenu(menu, forSegment: 0)
			addRemoveButtons?.target = self
		}
		if tableView != nil {
			tableView.setDraggingSourceOperationMask(.copy, forLocal: true)
			tableView.draggingDestinationFeedbackStyle = .none
			tableView.register(forDraggedTypes: FileDragTypes)
		}
		adjustForFileSelectionChange()
	}
	
	override func sessionChanged() {
		fileChangeDisposable?.dispose()
		fileChangeDisposable = session.workspace.fileChangeSignal.observeValues(filesRefreshed)
		loadData()
		tableView.reloadData()
	}
	
	override func appStatusChanged() {
		busyDisposable = appStatus?.busySignal.observe(on: UIScheduler()).observeValues { [weak self] isBusy in
			guard let tv = self?.tableView else { return }
			if isBusy {
				tv.unregisterDraggedTypes()
			} else {
				tv.register(forDraggedTypes: FileDragTypes)
			}
		}
	}
	
	func loadData() {
		var sectionedFiles = [[File](), [File](), [File]()]
		for aFile in session.workspace.files {
			if aFile.fileType.isSourceFile {
				sectionedFiles[0].append(aFile)
			} else if aFile.fileType.isImage {
				sectionedFiles[1].append(aFile)
			} else {
				sectionedFiles[2].append(aFile)
			}
		}
		//sort each one
		for var fa in sectionedFiles {
			fa.sort(by: { $0.name > $1.name })
		}
		rowData.removeAll()
		for i in 0..<sectionNames.count {
			if sectionedFiles[i].count > 0 {
				rowData.append(FileRowData(name: sectionNames[i], file: nil))
				rowData.append(contentsOf: sectionedFiles[i].map({ return FileRowData(name:nil, file:$0)}))
			}
		}
	}
	
	fileprivate func adjustForFileSelectionChange() {
		addRemoveButtons?.setEnabled(selectedFile != nil, forSegment: removeFileSegmentIndex)
	}
	
	override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		guard let action = menuItem.action else {
			return super.validateMenuItem(menuItem)
		}
		switch(action) {
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
		menu.items.forEach { $0.isEnabled = selectedFile != nil }
		menu.items.first(where: { $0.action == .promptToImport} )?.isEnabled = true
	}
	
	func fileDataIndex(fileId: Int) -> Int? {
		for (idx, data) in rowData.enumerated() {
			if data.file?.fileId == fileId { return idx }
		}
		return nil
	}
	
	// NSMenu calls this method before an item's action is called. we listen to it from the add button's menu
	func addFileMenuAction(_ note:Notification) {
		let menuItem = (note as NSNotification).userInfo!["MenuItem"] as! NSMenuItem
		let index = menuItem.representedObject as! Int
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
						//TODO: handle error
						self.logMessage("error creating empty file: %{public}s", result.error!.localizedDescription)
						return
					}
					self.select(fileId: fid)
				}
			}
		}
	}
	
	//MARK: - actions
	@IBAction func deleteFile(_ sender: AnyObject?) {
		guard let file = selectedFile else {
			logMessage("deleteFile should never be called without selected file")
			return
		}
		let defaults = UserDefaults.standard
		if defaults[.supressDeleteFileWarnings] {
			session.remove(file: file)
		}
		let alert = NSAlert()
		alert.showsSuppressionButton = true
		alert.messageText = NSLocalizedString(LocalStrings.deleteFileWarning, comment: "")
		alert.informativeText = NSLocalizedString(LocalStrings.deleteFileWarningInfo, comment: "")
		alert.addButton(withTitle: NSLocalizedString("Delete", comment: ""))
		alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
		alert.beginSheetModal(for: self.view.window!, completionHandler: { [weak alert] response in
			if let state = alert?.suppressionButton?.state , state == NSOnState {
				defaults[.supressDeleteFileWarnings] = true
			}
			if response != NSAlertFirstButtonReturn { return }
			//TODO: implement progress
			self.session.remove(file: file).startWithResult { result in
				guard let error = result.error else { return } //worked
				DispatchQueue.main.async {
					self.appStatus?.presentError(error, session: self.session)
				}
			}
			self.delegate?.fileSelectionChanged(nil)
		}) 
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
				self.session.duplicate(file: file, to: newName).startWithResult { result in
					// the id of the file that was created
					guard let fid = result.value else {
						//TODO: handle error
						self.logMessage("error duplicating file: %{public}s", result.error!.localizedDescription)
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
		guard let file = cellView.objectValue as? File else {
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
			self.session.rename(file: file, to: name).startWithResult { result in
				guard let error = result.error else {
					self.select(fileId: file.fileId)
					return
				}
				//TODO: handle error
				self.logMessage("error duplicating file: %{public}s", error.localizedDescription)
			}
		}
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

	@IBAction func exportSelectedFile(_ sender:AnyObject?) {
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
				os_log("why did we get error creating export bookmark: %{public}@", log: .app, type:.error, err)
			}
			savePanel.close()
			if result == NSFileHandlingPanelOKButton && savePanel.url != nil {
				do {
					try Foundation.FileManager.default.copyItem(at: self.session.fileCache.cachedUrl(file:self.selectedFile!), to: savePanel.url!)
				} catch let error as NSError {
					os_log("failed to copy file for export: %{public}@", log: .app, type:.error, error)
					let alert = NSAlert(error:error)
					alert.beginSheetModal(for: self.view.window!, completionHandler: { (response) -> Void in
						//do nothing
					}) 
				}
			}
		}
	}
	
	@IBAction func exportAllFiles(_ sender:AnyObject?) {
		//TODO: implement
	}
	
	//MARK: - private methods

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
		prompter.minimumStringLength = type.fileExtension.characters.count + 1
		let fileNames = session.workspace.files.map { return $0.name }
		prompter.validator = { (proposedName) in
			return fileNames.filter({$0.caseInsensitiveCompare(proposedName) == .orderedSame}).count == 0
		}
		prompter.prompt(window: self.view.window!) { (gotValue, value) in
			guard gotValue, var value = value else { handler(nil); return }
			if !value.hasSuffix(fileExtension) {
				value = value + fileExtension
			}
			handler(value)
		}
	}
	
	private func validateRename(file: File, newName: String?) -> Bool {
		guard var name = newName else { return true } //empty is allowable
		if !name.hasSuffix(".\(file.fileType.fileExtension)") {
			name += ".\(file.fileType.fileExtension)"
		}
		guard name.characters.count > 3 else { return false }
		//if same name, is valid
		guard name.caseInsensitiveCompare(file.name) != .orderedSame else { return true }
		//no duplicate names
		let fileNames = session.workspace.files.map { return $0.name }
		guard fileNames.filter({$0.caseInsensitiveCompare(name) == .orderedSame}).count == 0 else { return false }
		return true
	}
	
	private func importFiles(_ files:[FileImporter.FileToImport]) {
		let importer = try! FileImporter(files, fileCache:self.session.fileCache, connectInfo: session.conInfo)
		let (psignal, pobserver) = Signal<Double, Rc2Error>.pipe()
		//TODO: update progress
		importer.start().on(value: { (progress: FileImporter.ImportProgress) in
			pobserver.send(value: progress.percentComplete)
		}, failed: { (error) in
			//TODO: handle error
			os_log("got import error %{public}@", log: .app, type:.error, error.localizedDescription)
			pobserver.send(error: error)
		}, completed: {
			pobserver.sendCompleted()
			NotificationCenter.default.post(name: .FilesImported, object: self.fileImporter!)
			self.fileImporter = nil //free up importer
		}).start()
		//save reference so ARC does not dealloc importer
		self.fileImporter = importer
	}


	//MARK: - FileHandler implementation
	func filesRefreshed(_ changes: [CollectionChange<File>]?) {
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
	
	func select(file: File) {
		guard let idx = fileDataIndex(fileId: file.fileId) else {
			os_log("failed to find file to select", log: .app, type: .info)
			return
		}
		DispatchQueue.main.async {
			self.tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
		}
	}
	
	//MARK: - TableView datasource/delegate implementation
	func numberOfRows(in tableView: NSTableView) -> Int {
		return rowData.count
	}
	
	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		let data = rowData[row]
		if data.sectionName != nil {
			let tview = tableView.make(withIdentifier: "string", owner: nil) as! NSTableCellView
			tview.textField!.stringValue = data.sectionName!
			return tview
		} else {
			let fview = tableView.make(withIdentifier: "file", owner: nil) as! EditableTableCellView
			fview.objectValue = data.file
			fview.textField?.stringValue = data.file!.name
			return fview
		}
	}
	
	func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
		return rowData[row].sectionName != nil
	}
	
	func tableViewSelectionDidChange(_ notification: Notification) {
		adjustForFileSelectionChange()
		delegate?.fileSelectionChanged(selectedFile)
	}
	
	func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
		return rowData[row].file != nil
	}
	
	func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableViewDropOperation) -> NSDragOperation
	{
		return importPrompter!.validateTableViewDrop(info)
	}

	func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableViewDropOperation) -> Bool
	{
		importPrompter!.acceptTableViewDrop(info, workspace: session.workspace, window: view.window!) { (files) in
			self.importFiles(files)
		}
		return true
	}
}

//least hackish way to get segment's menu to show immediately if set, otherwise perform control's action
class AddRemoveSegmentedCell : NSSegmentedCell {
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


