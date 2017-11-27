//
//  SpreadsheetVariableDetailController.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Model
import SigmaSwiftStatistics

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
	
	func set(variable: Variable, source: SpreadsheetDataSource) -> NSSize {
		self.variable = variable
		self.ssheetSource = source
		ssheetTable.tableColumns.forEach { ssheetTable.removeTableColumn($0) }
		var estWidth: CGFloat = 0
		let font = NSFont.userFont(ofSize: 14.0)
		let fontAttrs: [NSAttributedStringKey: Any] = [NSAttributedStringKey.font: font as Any]
		// create row header column
		if source.columnNames != nil {
			let headColumn = NSTableColumn(identifier: .rowHeaderColumn)
			headColumn.width = 40.0
			headColumn.title = ""
			ssheetTable.addTableColumn(headColumn)
			columnIndexes[headColumn] = 0
			colOffset = 0
			estWidth += headColumn.width
		}
		// create data columns
		for colIdx in 0..<source.columnCount {
			//var colWidth: CGFloat = 40.0
			let widths = source.values(forColumn: colIdx).map { Double(($0 as NSString).size(withAttributes: fontAttrs).width) }
			let aColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(rawValue: String(colIdx + colOffset)))
			var headerWidth: Double = 0
			if let colName = source.columnNames?[colIdx] {
				aColumn.title = colName
			//	colWidth = max(colWidth, (colName as NSString).size(withAttributes: fontAttrs).width)
				headerWidth = Double((colName as NSString).size(withAttributes: fontAttrs).width)
			}
			
			let avgWidth = Sigma.average(widths) ?? 20 // if average return nil (which it will if there are no widths) use 20
			let maxWidth = max(headerWidth, Sigma.max(widths)!)
			let stdDev = Sigma.standardDeviationPopulation(widths) ?? 0 // if stdDev returns nil, use 0 as the value
			let desiredWidth = min(maxWidth,  avgWidth + (2.0 * stdDev))
			aColumn.width = CGFloat(min(desiredWidth.rounded(), 40)) + 16 //16 is std offset (8) for each side of label
			ssheetTable.addTableColumn(aColumn)
			columnIndexes[aColumn] = colIdx + colOffset
			estWidth += aColumn.width
		}
		if source.columnNames == nil {
			ssheetTable.headerView = nil
		} else {
			ssheetTable.headerView = NSTableHeaderView()
		}
		ssheetTable.reloadData()
		let idealHeight = CGFloat(80 + (source.rowCount * 32))
		let sz = NSSize(width: min(max(estWidth, 400), 300), height: min(max(idealHeight, 600), 240))
		print("df \(estWidth) x \(idealHeight), actual = \(sz)")
		return sz
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
