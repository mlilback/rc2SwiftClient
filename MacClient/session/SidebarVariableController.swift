//
//  SidebarVariableController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
fileprivate func < <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l < r
  case (nil, _?):
    return true
  default:
    return false
  }
}

fileprivate func >= <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l >= r
  default:
    return !(lhs < rhs)
  }
}



class SidebarVariableController : AbstractSessionViewController, VariableHandler, NSTableViewDataSource, NSTableViewDelegate {
	var rootVariables:[Variable] = []
	var changedIndexes:Set<Int> = []
	var variablePopover:NSPopover?
	var isVisible = false
	@IBOutlet var varTableView:NSTableView?
	
	override func viewWillAppear() {
		super.viewWillAppear()
		if sessionOptional != nil {
			session.startWatchingVariables()
		}
		isVisible = true
	}
	
	override func viewWillDisappear() {
		super.viewWillDisappear()
		if sessionOptional != nil {
			session.stopWatchingVariables()
		}
		isVisible = false
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()
	}
	
	override func sessionChanged() {
		if isVisible {
			session.startWatchingVariables()
		}
	}
	
	func variableNamed(_ name:String?) -> Variable? {
		return rootVariables.filter({ $0.name == name }).first
	}
	
	func handleVariableMessage(_ single:Bool, variables:[Variable]) {
		if single {
			if let curVal = variableNamed(variables[0].name) {
				rootVariables[rootVariables.index(of: curVal)!] = curVal
			} else {
				rootVariables.append(variables.first!)
			}
		} else {
			rootVariables = variables
		}
		rootVariables.sort { (lhs, rhs) -> Bool in
			return lhs.name < rhs.name
		}
		varTableView?.reloadData()
	}
	
	func handleVariableDeltaMessage(_ assigned: [Variable], removed: [String]) {
		for (_, variable) in assigned.enumerated() {
			if let curVal = variableNamed(variable.name) {
				rootVariables[rootVariables.index(of: curVal)!] = variable
			} else {
				rootVariables.append(variable)
			}
		}
		removed.forEach() { str in
			if let curVal = variableNamed(str) {
				rootVariables.remove(at: rootVariables.index(of: curVal)!)
			}
		}
		varTableView?.reloadData()
	}
	
	//MARK: NSTableViewDataSource
	func numberOfRows(in tableView: NSTableView) -> Int {
		return rootVariables.count
	}
	
	//MARK: NSTableViewDelegate
	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
	{
		let isValue = tableColumn!.identifier == "value"
		let cellIdent = isValue ? "varValueView" : "varNameView"
		let view:NSTableCellView = tableView.make(withIdentifier: cellIdent, owner: self) as! NSTableCellView
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

	func tableView(_ tableView: NSTableView, selectionIndexesForProposedSelection proposedSelectionIndexes: IndexSet) -> IndexSet
	{
		guard proposedSelectionIndexes.count > 0 else { return proposedSelectionIndexes }
		let variable = rootVariables[proposedSelectionIndexes.first!]
		if variable.count <= 1 && variable.primitiveType != .NA { return tableView.selectedRowIndexes }
		return proposedSelectionIndexes
	}
	
	func tableViewSelectionDidChange(_ notification: Notification)
	{
		//if no selection, dismiss popover if visible
		guard varTableView?.selectedRow >= 0 else {
			if variablePopover?.isShown ?? false { variablePopover?.close(); variablePopover = nil }
			return
		}
		
	}
}
