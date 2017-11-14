//
//  VariableDetailsViewController.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Model

fileprivate extension NSUserInterfaceItemIdentifier {
	static let valueCell = NSUserInterfaceItemIdentifier("variableValue")
}

class VariableDetailsViewController: NSViewController {
	@IBOutlet var valuesTableView: NSTableView!
	var variable: Variable? { didSet { valuesTableView?.reloadData() }}
}

extension VariableDetailsViewController: NSTableViewDataSource {
	func numberOfRows(in tableView: NSTableView) -> Int {
		return variable?.length ?? 0
	}
}

extension VariableDetailsViewController: NSTableViewDelegate {
	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		guard let cellView = tableView.makeView(withIdentifier: .valueCell, owner: nil) as? NSTableCellView else { fatalError("failed to load table cell view") }
		cellView.textField?.stringValue = "some value"
		return cellView
	}
}

