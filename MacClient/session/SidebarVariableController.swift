//
//  SidebarVariableController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa


class SidebarVariableController : AbstractSessionViewController, VariableHandler, NSTableViewDataSource, NSTableViewDelegate {
	var rootVariables:[Variable] = []
	var changedIndexes:Set<Int> = []
	
	
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
	
	func handleVariableMessage(socketId:Int, delta:Bool, single:Bool, variables:[Variable]) {
	
	}
	
	//MARK: NSTableViewDataSource
	func numberOfRowsInTableView(tableView: NSTableView) -> Int {
		return rootVariables.count
	}
	
	//MARK: NSTableViewDelegate
	func tableView(tableView: NSTableView, viewForTableColumn tableColumn: NSTableColumn?, row: Int) -> NSView? {
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
	
}
