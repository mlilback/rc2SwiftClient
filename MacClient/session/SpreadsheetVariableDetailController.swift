//
//  SpreadsheetVariableDetailController.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Model

fileprivate extension NSUserInterfaceItemIdentifier {
	static let ssheetHead = NSUserInterfaceItemIdentifier("ssheetHead")
	static let ssheetCell = NSUserInterfaceItemIdentifier("ssheetValue")
	static let rowHeaderColumn = NSUserInterfaceItemIdentifier("rowHeader")
}

class SpreadsheetVariableDetailController: NSViewController {
	@IBOutlet var ssheetTable: NSTableView!
	private(set) var variable: Variable!
	private var ssheetSource: SpreadsheetDataSource?
	private var columnIndexes = [NSTableColumn: Int]()
	private var colOffset = 1
	
	func set(variable: Variable, source: SpreadsheetDataSource) {
		self.variable = variable
		self.ssheetSource = source
		ssheetTable.tableColumns.forEach { ssheetTable.removeTableColumn($0) }
		// create row header column
		if source.columnNames != nil {
			let headColumn = NSTableColumn(identifier: .rowHeaderColumn)
			headColumn.width = 40.0
			headColumn.title = ""
			ssheetTable.addTableColumn(headColumn)
			columnIndexes[headColumn] = 0
			colOffset = 0
		}
		// create data columns
		for idx in 0..<source.columnCount {
			let aColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(rawValue: String(idx + colOffset)))
			if let colName = source.columnNames?[idx] {
				aColumn.title = colName
			}
			aColumn.width = 40.0
			ssheetTable.addTableColumn(aColumn)
			columnIndexes[aColumn] = idx + colOffset
		}
		if source.columnNames == nil {
			ssheetTable.headerView = nil
		} else {
			ssheetTable.headerView = NSTableHeaderView()
		}
		ssheetTable.reloadData()
	}
}

extension SpreadsheetVariableDetailController: NSTableViewDataSource {
	func numberOfRows(in tableView: NSTableView) -> Int {
		return ssheetSource?.rowCount ?? 0
	}
}

extension SpreadsheetVariableDetailController: NSTableViewDelegate {
	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		guard let column = tableColumn, let columnIndex = columnIndexes[column] else { return nil }
		var cellIdent = NSUserInterfaceItemIdentifier.ssheetCell
		var cellString = ""
		if tableColumn?.identifier == .rowHeaderColumn {
			cellIdent = .ssheetHead
			if let rowName = ssheetSource?.rowNames?[row] {
				cellString = rowName
			}
		} else {
			cellString = ssheetSource?.value(atRow: row, column: columnIndex - colOffset) ?? ""
		}
		guard let cellView = tableView.makeView(withIdentifier: cellIdent, owner: nil) as? NSTableCellView
			else { fatalError("failed to load table cell view") }
		cellView.textField?.stringValue = cellString
		return cellView
	}
}
