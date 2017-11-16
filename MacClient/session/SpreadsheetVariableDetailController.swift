//
//  SpreadsheetVariableDetailController.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Model

fileprivate extension NSUserInterfaceItemIdentifier {
	static let ssheetCell = NSUserInterfaceItemIdentifier("ssheetValue")
}

class SpreadsheetVariableDetailController: NSViewController {
	@IBOutlet var ssheetTable: NSTableView!
	private(set) var variable: Variable!
	private var ssheetSource: SpreadsheetDataSource?
	private var columnIndexes = [NSTableColumn: Int]()
	
	func set(variable: Variable, source: SpreadsheetDataSource) {
		self.variable = variable
		self.ssheetSource = source
		ssheetTable.tableColumns.forEach { ssheetTable.removeTableColumn($0) }
		for idx in 0..<source.columnCount {
			let aColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(rawValue: String(idx)))
			if let colName = source.columnNames?[idx] {
				aColumn.title = colName
			}
			ssheetTable.addTableColumn(aColumn)
			columnIndexes[aColumn] = idx
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
		guard let cellView = tableView.makeView(withIdentifier: .ssheetCell, owner: nil) as? NSTableCellView
			else { fatalError("failed to load table cell view") }
		cellView.textField?.stringValue = ssheetSource?.value(atRow: row, column: columnIndex) ?? ""
		return cellView
	}
}
