//
//  SidebarVariableController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa


class SidebarVariableController : AbstractSessionViewController, VariableHandler, NSTableViewDataSource, NSTableViewDelegate {
	var rootVariables:[Variable] = []
	var changedIndexes:Set<Int> = []
	var variablePopover:NSPopover?
	@IBOutlet var varTableView:NSTableView?
	
	override func viewWillAppear() {
		super.viewWillAppear()
		if sessionOptional != nil {
			session.startWatchingVariables()
		}
	}
	
	override func viewWillDisappear() {
		super.viewWillDisappear()
		if sessionOptional != nil {
			session.stopWatchingVariables()
		}
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()
		log.info("vars loaded")
	}
	
	override func sessionChanged() {
		session.startWatchingVariables()
	}
	
	func variableNamed(name:String?) -> Variable? {
		return rootVariables.filter({ $0.name == name }).first
	}
	
	func handleVariableMessage(single:Bool, variables:[Variable]) {
		if single {
			if let curVal = variableNamed(variables[0].name) {
				rootVariables[rootVariables.indexOf(curVal)!] = curVal
			} else {
				rootVariables.append(variables.first!)
			}
		} else {
			rootVariables = variables
		}
		rootVariables.sortInPlace { (lhs, rhs) -> Bool in
			return lhs.name < rhs.name
		}
		varTableView?.reloadData()
	}
	
	func handleVariableDeltaMessage(assigned: [Variable], removed: [String]) {
		for (_, variable) in assigned.enumerate() {
			if let curVal = variableNamed(variable.name) {
				rootVariables[rootVariables.indexOf(curVal)!] = variable
			} else {
				rootVariables.append(variable)
			}
		}
		removed.forEach() { str in
			if let curVal = variableNamed(str) {
				rootVariables.removeAtIndex(rootVariables.indexOf(curVal)!)
			}
		}
		varTableView?.reloadData()
	}
	
	//MARK: NSTableViewDataSource
	func numberOfRowsInTableView(tableView: NSTableView) -> Int {
		return rootVariables.count
	}
	
	//MARK: NSTableViewDelegate
	func tableView(tableView: NSTableView, viewForTableColumn tableColumn: NSTableColumn?, row: Int) -> NSView?
	{
		let isValue = tableColumn!.identifier == "value"
		let cellIdent = isValue ? "varValueView" : "varNameView"
		let view:NSTableCellView = tableView.makeViewWithIdentifier(cellIdent, owner: self) as! NSTableCellView
		let variable = rootVariables[row]
		view.textField?.stringValue = isValue ? variable.description : variable.name ?? ""
		if changedIndexes.contains(row) {
			view.textField?.backgroundColor = VariableUpdatedBackgroundColor
			view.textField?.drawsBackground = true
		} else {
			view.textField?.backgroundColor = VariableNormalBackgroundColor
			view.textField?.drawsBackground = false
		}
		view.textField?.toolTip = isValue ? variable.summary : ""
		return view
	}

	func tableView(tableView: NSTableView, selectionIndexesForProposedSelection proposedSelectionIndexes: NSIndexSet) -> NSIndexSet
	{
		guard proposedSelectionIndexes.count > 0 else { return proposedSelectionIndexes }
		let variable = rootVariables[proposedSelectionIndexes.firstIndex]
		if variable.count <= 1 && variable.primitiveType != .NA { return tableView.selectedRowIndexes }
		return proposedSelectionIndexes
	}
	
	func tableViewSelectionDidChange(notification: NSNotification)
	{
		//if no selection, dismiss popover if visible
		guard varTableView?.selectedRow >= 0 else {
			if variablePopover?.shown ?? false { variablePopover?.close(); variablePopover = nil }
			return
		}
		
	}
}
