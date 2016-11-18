//
//  SidebarFileController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import os
import ReactiveSwift
import SwiftyUserDefaults
import NotifyingCollection
import ClientCore
import Networking

// MARK: Keys for UserDefaults
extension DefaultsKeys {
	static let lastExportDirectory = DefaultsKey<Data?>("rc2.LastExportDirectory")
}

///selectors used in this file, aliased with shorter, descriptive names
private extension Selector {
	static let addDocument = #selector(SidebarFileController.addDocumentOfType(_:))
	static let addFileMenu =  #selector(SidebarFileController.addFileMenuAction(_:))
	static let addButtonClicked = #selector(SidebarFileController.addButtonClicked(_:))
	static let receivedStatusChange = #selector(SidebarFileController.receivedStatusChange(_:))
	static let promptToImport = #selector(SidebarFileController.promptToImportFiles(_:))
	static let exportSelectedFile = #selector(SidebarFileController.exportSelectedFile(_:))
	static let exportAll = #selector(SidebarFileController.exportAllFiles(_:))
}

class FileRowData {
	var sectionName: String?
	var file: File?
	init(name: String?, file: File?) {
		self.sectionName = name
		self.file = file
	}
}

protocol FileViewControllerDelegate: class {
	func fileSelectionChanged(_ file: File?)
	func renameFile(_ file:File, to: String)
	func importFiles(_ files: [URL])
}

let FileDragTypes = [kUTTypeFileURL as String]

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
			addRemoveButtons?.action = .addButtonClicked
		}
		if tableView != nil {
			tableView.setDraggingSourceOperationMask(.copy, forLocal: true)
			tableView.draggingDestinationFeedbackStyle = .none
			tableView.register(forDraggedTypes: FileDragTypes)
		}
	}
	
	override func sessionChanged() {
		fileChangeDisposable?.dispose()
		fileChangeDisposable = session.workspace.fileChangeSignal.observeValues(filesRefreshed)
		loadData()
		tableView.reloadData()
	}
	
	func receivedStatusChange(_ note:Notification) {
		assert(self.appStatus != nil, "appStatus not set on SidebarFileController")
		if let tv = self.tableView, let apps = self.appStatus {
			if apps.busy {
				tv.unregisterDraggedTypes()
			} else {
				tv.register(forDraggedTypes: FileDragTypes)
			}
		}
	}
	
	override func appStatusChanged() {
		NotificationCenter.default.addObserver(self, selector: .receivedStatusChange, name: NSNotification.Name(rawValue: Notifications.AppStatusChanged), object: nil)
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
	
	func menuNeedsUpdate(_ menu: NSMenu) {
		menu.items.filter() { item in
			return item.action == .promptToImport
		}.first?.isEnabled = selectedFile != nil
	}
	
	//MARK: - actions
	func addButtonClicked(_ sender:AnyObject?) {
		os_log("called for %d", type:.info, (addRemoveButtons?.selectedSegment)!)
		if addRemoveButtons?.selectedSegment == 0 {
			//add file
			//TODO: implement add file
		} else {
			//delete file
			deleteFile(sender)
		}
	}
	
	func addFileMenuAction(_ note:Notification) {
		let menuItem = (note as NSNotification).userInfo!["MenuItem"] as! NSMenuItem
		let index = menuItem.representedObject as! Int
		let fileType = FileType.creatableFileTypes[index]
		print("add file of type \(fileType.name)")
	}
	
	@IBAction func deleteFile(_ sender:AnyObject?) {
		guard let file = selectedFile else { return }
		let defaults = UserDefaults.standard
		if defaults.bool(forKey: PrefKeys.SupressDeleteFileWarning) {
			session.remove(file: file)
		}
		let alert = NSAlert()
		alert.showsSuppressionButton = true
		alert.messageText = NSLocalizedString(LStrings.DeleteFileWarning, comment: "")
		alert.informativeText = NSLocalizedString(LStrings.DeleteFileWarningInfo, comment: "")
		alert.addButton(withTitle: NSLocalizedString("Delete", comment: ""))
		alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
		alert.beginSheetModal(for: self.view.window!, completionHandler: { [weak alert] response in
			if let state = alert?.suppressionButton?.state , state == NSOnState {
				defaults.set(true, forKey: PrefKeys.SupressDeleteFileWarning)
			}
			if response != NSAlertFirstButtonReturn { return }
			self.session.remove(file: file)
			self.delegate?.fileSelectionChanged(nil)
		}) 
	}
	
	@IBAction func duplicateFile(_ sender:AnyObject?) {
		//TODO: implement duplicateFile
		os_log("duplicate selected file", type:.info)
	}

	@IBAction func renameFile(_ sender:AnyObject?) {
		//TODO: implement renameFile
		os_log("rename selcted file", type:.info)
	}
	
	@IBAction func addDocumentOfType(_ menuItem:NSMenuItem) {
		//TODO: implement addDocumentOfType
		os_log("add file of type %{public}s", type:.info, menuItem)
	}
	
	@IBAction func segButtonClicked(_ sender:AnyObject?) {
		if addRemoveButtons?.selectedSegment == 0 {
			//add file
			//TODO: implement add file
		} else {
			//delete file
			deleteFile(sender)
		}
	}

	//MARK: - import/export
	@IBAction func promptToImportFiles(_ sender:Any?) {
		if nil == importPrompter {
			importPrompter = MacFileImportSetup()
		}
		importPrompter!.performFileImport(view.window!, workspace: session.workspace) { files in
			guard files != nil else { return } //user canceled import
			self.importFiles(files!)
		}
	}

	func importFiles(_ files:[FileImporter.FileToImport]) {
		let importer = try! FileImporter(files, fileCache:self.session.fileCache, connectInfo: session.conInfo)
		let (psignal, pobserver) = Signal<Double, Rc2Error>.pipe()
		appStatus?.monitorProgress(signal: psignal)
		importer.start().on(value: { (progress: FileImporter.ImportProgress) in
			pobserver.send(value: progress.percentComplete)
		}, failed: { (error) in
			//TODO: handle error
			os_log("got import error %{public}s", type:.error, error.localizedDescription)
			pobserver.send(error: error)
		}, completed: {
			pobserver.sendCompleted()
			self.fileImporter = nil //free up importer
		}).start()
		//save reference so ARC does not dealloc importer
		self.fileImporter = importer
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
				os_log("why did we get error creating export bookmark: %{public}s", type:.error, err)
			}
			savePanel.close()
			if result == NSFileHandlingPanelOKButton && savePanel.url != nil {
				do {
					try Foundation.FileManager.default.copyItem(at: self.session.fileCache.cachedUrl(file:self.selectedFile!), to: savePanel.url!)
				} catch let error as NSError {
					os_log("failed to copy file for export: %{public}s", type:.error, error)
					let alert = NSAlert(error:error)
					alert.beginSheetModal(for: self.view.window!, completionHandler: { (response) -> Void in
						//do nothing
					}) 
				}
			}
		}
	}
	
	@IBAction func exportAllFiles(_ sender:AnyObject?) {
		
	}

	//MARK: - FileHandler implementation
	func filesRefreshed(_ changes: [CollectionChange<File>]?) {
		//TODO: ideally should figure out what file was changed and animate the tableview update instead of refreshing all rows
		//TODO: updated file always shows last, which is wrong
		loadData()
		tableView.reloadData()
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
			let fview = tableView.make(withIdentifier: "file", owner: nil) as! SessionCellView
			fview.file = data.file
			fview.editComplete = { self.delegate?.renameFile($0.file!, to: $0.nameField.stringValue) }
			return fview
		}
	}
	
	func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
		return rowData[row].sectionName != nil
	}
	
	func tableViewSelectionDidChange(_ notification: Notification) {
		delegate?.fileSelectionChanged(selectedFile)
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

open class SessionCellView : NSTableCellView, NSTextFieldDelegate {
	@IBOutlet var nameField: NSTextField!
	var file:File? {
		didSet { nameField?.stringValue = (file?.name)! }
	}

	var editComplete:((_ cell:SessionCellView) -> Void)?
	
	open override func controlTextDidEndEditing(_ obj: Notification) {
		nameField.isEditable = false
		editComplete?(self)
		nameField.stringValue = (file?.name)!
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


