//
//  ValuesVariableDetailController.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Model

fileprivate extension NSUserInterfaceItemIdentifier {
	static let valueCell = NSUserInterfaceItemIdentifier("variableValue")
}

class ValuesVariableDetailController: NSViewController {
	@IBOutlet var valuesTableView: NSTableView!
	private(set) var variable: Variable?
	private(set) var valueContent: [String] = []
	
	func set(variable: Variable, values: [String]) {
		self.variable = variable
		self.valueContent = values
		valuesTableView?.reloadData()
	}
}

extension ValuesVariableDetailController: NSTableViewDataSource {
	func numberOfRows(in tableView: NSTableView) -> Int {
		return valueContent.count
	}
}

extension ValuesVariableDetailController: NSTableViewDelegate {
	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		guard let cellView = tableView.makeView(withIdentifier: .valueCell, owner: nil) as? NSTableCellView
			else { fatalError("failed to load table cell view") }
		cellView.textField?.stringValue = valueContent[row]
		return cellView
	}
}
