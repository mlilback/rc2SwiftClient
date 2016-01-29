//
//  FileViewContrfoller.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

class FileRowData {
	var sectionName:String?
	var file:File?
	init(name:String?, file:File?) {
		self.sectionName = name
		self.file = file
	}
}

protocol FileViewControllerDelegate: class {
	func fileSelectionChanged(file:File, oldSelection:File)
	func renameFile(file:File, to:String)
}
//TODO: make sure when delegate renames file our list gets updated

class FileViewContrfoller: AbstractSessionViewController, NSTableViewDataSource, NSTableViewDelegate {
	let sectionNames:[String] = ["Source Files", "Images", "Other"]

	@IBOutlet var tableView: NSTableView!
	var rowData:[FileRowData] = [FileRowData]()
	var delegate:FileViewControllerDelegate?
	
	var selectedFile:File? {
		guard tableView.selectedRow >= 0 else { return nil }
		return rowData[tableView.selectedRow].file
	}
	
//	override func viewDidLoad() {
//		super.viewDidLoad()
//		loadData()
//		tableView.reloadData()
//	}
	
	override func sessionChanged() {
		loadData()
		tableView.reloadData()
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
			fa.sortInPlace({ $0.name > $1.name })
		}
		rowData.removeAll()
		for i in 0..<sectionNames.count {
			if sectionedFiles[i].count > 0 {
				rowData.append(FileRowData(name: sectionNames[i], file: nil))
				rowData.appendContentsOf(sectionedFiles[i].map({ return FileRowData(name:nil, file:$0)}))
			}
		}
	}
	
	func numberOfRowsInTableView(tableView: NSTableView) -> Int {
		return rowData.count
	}
	
	func tableView(tableView: NSTableView, viewForTableColumn tableColumn: NSTableColumn?, row: Int) -> NSView? {
		let data = rowData[row]
		if data.sectionName != nil {
			let tview = tableView.makeViewWithIdentifier("string", owner: nil) as! NSTableCellView
			tview.textField!.stringValue = data.sectionName!
			return tview
		} else {
			let fview = tableView.makeViewWithIdentifier("file", owner: nil) as! SessionCellView
			fview.file = data.file
			fview.editComplete = { self.delegate?.renameFile($0.file!, to: $0.nameField.stringValue) }
			return fview
		}
	}
	
	func tableView(tableView: NSTableView, isGroupRow row: Int) -> Bool {
		return rowData[row].sectionName != nil
	}
	
	func tableViewSelectionDidChange(notification: NSNotification) {
		NSNotificationCenter.defaultCenter().postNotificationName( SessionFileSelectionChangedNotification, object: selectedFile)
	}
}

public class SessionCellView : NSTableCellView, NSTextFieldDelegate {
	@IBOutlet var nameField: NSTextField!
	var file:File? {
		didSet { nameField?.stringValue = (file?.name)! }
	}

	var editComplete:((cell:SessionCellView) -> Void)?
	
	public override func controlTextDidEndEditing(obj: NSNotification) {
		nameField.editable = false
		editComplete?(cell: self)
		nameField.stringValue = (file?.name)!
	}
}



