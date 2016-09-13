//
//  SidebarFileController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import os

class FileRowData {
	var sectionName:String?
	var file:File?
	init(name:String?, file:File?) {
		self.sectionName = name
		self.file = file
	}
}

protocol FileViewControllerDelegate: class {
	func fileSelectionChanged(_ file:File?)
	func renameFile(_ file:File, to:String)
	func importFiles(_ files:[URL])
}

let FileDragTypes = [kUTTypeFileURL as String]
let LastExportDirectoryKey = "rc2.LastExportDirectory"

//TODO: make sure when delegate renames file our list gets updated

class SidebarFileController: AbstractSessionViewController, NSTableViewDataSource, NSTableViewDelegate, FileHandler, NSOpenSavePanelDelegate, NSMenuDelegate
{
	//MARK: properties
	let sectionNames:[String] = ["Source Files", "Images", "Other"]

	@IBOutlet var tableView: NSTableView!
	@IBOutlet var addRemoveButtons:NSSegmentedControl?
	var rowData:[FileRowData] = [FileRowData]()
	var delegate:FileViewControllerDelegate?
	lazy var importPrompter:MacFileImportSetup? = { MacFileImportSetup() }()
	var fileImporter:FileImporter?
	
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
				let mi = NSMenuItem(title: aType.details, action: #selector(SidebarFileController.addDocumentOfType(_:)), keyEquivalent: "")
				mi.representedObject = index
				menu.addItem(mi)
			}
			menu.autoenablesItems = false
			//NOTE: the action method of the menu item wasn't being called the first time. This works all times.
			NotificationCenter.default.addObserver(self, selector: #selector(SidebarFileController.addFileMenuAction(_:)), name: NSNotification.Name.NSMenuDidSendAction, object: menu)
			addRemoveButtons?.setMenu(menu, forSegment: 0)
			addRemoveButtons?.target = self
			addRemoveButtons?.action = #selector(SidebarFileController.addButtonClicked(_:))
		}
		if tableView != nil {
			tableView.setDraggingSourceOperationMask(.copy, forLocal: true)
			tableView.draggingDestinationFeedbackStyle = .none
			tableView.register(forDraggedTypes: FileDragTypes)
			NotificationCenter.default.addObserver(self, selector: #selector(FileHandler.filesRefreshed(_:)), name: WorkspaceFileChangedNotification, object: nil)
		}
	}
	
	override func sessionChanged() {
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
		NotificationCenter.default.addObserver(self, selector: #selector(SidebarFileController.receivedStatusChange(_:)), name: NSNotification.Name(rawValue: Notifications.AppStatusChanged), object: nil)
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
		switch(menuItem.action) {
			case (#selector(FileHandler.promptToImportFiles(_:)))?:
				return true
			case (#selector(SidebarFileController.exportSelectedFile(_:)))?:
				return selectedFile != nil
			case (#selector(SidebarFileController.exportAllFiles(_:)))?:
				return true
			default:
				return super.validateMenuItem(menuItem)
		}
	}
	
	func menuNeedsUpdate(_ menu: NSMenu) {
		menu.items.filter() { item in
			return item.action == #selector(SidebarFileController.exportSelectedFile(_:))
		}.first?.isEnabled = selectedFile != nil
	}
	
	//MARK: - actions
	func addButtonClicked(_ sender:AnyObject?) {
		os_log("called for %{public}@", type:.info, (addRemoveButtons?.selectedSegment)!)
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
		assert(selectedFile != nil)
		session.removeFile(selectedFile!)
		os_log("remove selected file", type:.info)
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
		os_log("add file of type %{public}@", type:.info, menuItem)
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
	@IBAction func promptToImportFiles(_ sender:AnyObject?) {
		if nil == importPrompter {
			importPrompter = MacFileImportSetup()
		}
		importPrompter!.performFileImport(view.window!, workspace: session.workspace) { files in
			guard files != nil else { return } //user canceled import
			self.importFiles(files!)
		}
	}
	
	func importFiles(_ files:[FileToImport]) {
		let importer = FileImporter(files, fileHandler:self.session.fileHandler, baseUrl:session.restServer!.baseUrl!, configuration: session.restServer!.urlConfig)
		{ (progress:Progress) in
			if progress.rc2_error != nil {
				//TODO: handle error
				os_log("got import error %{public}@", type:.error, progress.rc2_error as! NSError)
			}
			self.appStatus?.currentProgress = nil
			self.fileImporter = nil //free up importer
		}
		self.appStatus?.currentProgress = importer.progress
		do {
			try importer.startImport()
		} catch let err {
			os_log("failed to start import: %{public}@", type:.error, err as NSError)
			//TODO: report error to user
		}
		//save reference so ARC does not dealloc importer
		self.fileImporter = importer
	}
	
	@IBAction func exportSelectedFile(_ sender:AnyObject?) {
		let defaults = UserDefaults.standard
		let savePanel = NSSavePanel()
		savePanel.isExtensionHidden = false
		savePanel.allowedFileTypes = [(selectedFile?.fileType.fileExtension)!]
		savePanel.nameFieldStringValue = (selectedFile?.name)!
		if let bmarkData = defaults.object(forKey: LastExportDirectoryKey) as? Data {
			do {
				savePanel.directoryURL = try (NSURL(resolvingBookmarkData: bmarkData, options: [], relativeTo: nil, bookmarkDataIsStale: nil) as URL)
			} catch {
			}
		}
		savePanel.beginSheetModal(for: view.window!) { result in
			do {
				let bmark = try (savePanel.directoryURL as NSURL?)?.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
				defaults.set(bmark, forKey: LastExportDirectoryKey)
			} catch let err as NSError {
				os_log("why did we get error creating export bookmark: %{public}@", type:.error, err)
			}
			savePanel.close()
			if result == NSFileHandlingPanelOKButton && savePanel.url != nil {
				do {
					try Foundation.FileManager.default.copyItem(at: self.session.fileHandler.fileCache.cachedFileUrl(self.selectedFile!), to: savePanel.url!)
				} catch let error as NSError {
					os_log("failed to copy file for export: %{public}@", type:.error, error)
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
	func filesRefreshed(_ note:Notification?) {
		if let _ = (note as NSNotification?)?.userInfo?["change"] as? WorkspaceFileChange {
			//TODO: ideally should figure out what file was changed and animate the tableview update instead of refreshing all rows
			//TODO: updated file always shows last, which is wrong
			loadData()
			tableView.reloadData()
		} else {
			os_log("got filechangenotification without a change object", type:.error)
			//reload it all
			loadData()
			tableView.reloadData()
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
			//TODO: import the files
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


