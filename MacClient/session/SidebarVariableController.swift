//
//  SidebarVariableController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import Networking
import os
import SwiftyUserDefaults
import Model

class SidebarVariableController: AbstractSessionViewController {
	// MARK: properties
	var rootVariables: [Variable] = []
	var changedIndexes: Set<Int> = []
	var variablePopover: NSPopover?
	var isVisible = false
	@IBOutlet var varTableView: NSTableView!
	@IBOutlet var clearButton: NSButton!
	@IBOutlet var contextMenu: NSMenu!
	var detailsPopup: NSPopover?
	var detailsController: VariableDetailsViewController?
	
	// MARK: methods
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
	
	override func awakeFromNib() {
		super.awakeFromNib()
		varTableView?.setDraggingSourceOperationMask(.copy, forLocal: false)
		varTableView?.doubleAction = #selector(SidebarVariableController.doubleClick(_:))
	}
	
	override func sessionChanged() {
		if isVisible {
			session.startWatchingVariables()
		}
	}
	
	func variableNamed(_ name: String?) -> Variable? {
		return rootVariables.first(where: { $0.name == name })
	}
	
	@IBAction func delete(_ sender: Any?) {
		guard let selRow = varTableView?.selectedRow,
			selRow >= 0,
			selRow < rootVariables.count
		else {
			os_log("attempt to delete incorrect variable", log: .app, type: .error)
			return
		}
		session.deleteVariable(name: rootVariables[selRow].name)
	}
	
	@IBAction func copy(_ sender: AnyObject?) {
		guard let row = varTableView?.selectedRow, row >= 0 else { return }
		let pasteboard = NSPasteboard.general
		pasteboard.clearContents()
		do {
			let jsonStr = String(data: try session.conInfo.encode(rootVariables[row]), encoding: .utf8)
			// swiftlint:disable:next force_try
			pasteboard.setString(jsonStr!, forType: .variable)
			pasteboard.setString(rootVariables[row].description, forType: .string)
		} catch {
			os_log("error copying varable to window: %{public}@", log: .app, error as NSError)
		}
	}
	
	@IBAction func clearWorkspace(_ sender: Any?) {
		confirmAction(message: NSLocalizedString(LocalStrings.clearWorkspaceWarning, comment: ""),
		              infoText: NSLocalizedString(LocalStrings.clearWorkspaceWarningInfo, comment: ""),
		              buttonTitle: NSLocalizedString("Clear", comment: ""),
		              suppressionKey: .suppressClearWorkspace)
		{ (confirmed) in
			guard confirmed else { return }
			self.session.clearVariables()
		}
	}
	
	@IBAction func showDetails(_ sender: Any?) {
		if variablePopover == nil {
			// setup the popup and view controller
			let sboard = NSStoryboard(name: .mainController, bundle: nil)
			detailsController = sboard.instantiateViewController()
			assert(detailsController != nil)
			variablePopover = NSPopover()
			variablePopover?.behavior = .transient
			variablePopover?.contentViewController = detailsController
			variablePopover?.contentSize = NSSize(width: 200, height: 300)
		}
		let selRow = varTableView.selectedRow
		guard selRow != -1 else { os_log("can't show variable details w/o selection", log: .app); return }
		// if the view isn't loaded, we need to display the view first, then tell it what variable to show
		guard detailsController!.isViewLoaded else {
			variablePopover?.show(relativeTo: varTableView.rect(ofRow: selRow), of: varTableView, preferredEdge: .maxX)
			detailsController?.display(variable: rootVariables[selRow])
			return
		}
		// we need to delay showing the popover because NSTabViewController wants to animate this, we don't want it animated
		detailsController?.display(variable: rootVariables[selRow])
		DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) {
			self.variablePopover?.show(relativeTo: self.varTableView.rect(ofRow: selRow), of: self.varTableView, preferredEdge: .maxX)
		}
	}
	
	@IBAction func doubleClick(_ sender: Any?) {
		guard varTableView.clickedColumn == 1 && varTableView.clickedRow != -1 else { return }
		showDetails(sender)
	}
	
	func variablesChanged() {
		varTableView?.reloadData()
		clearButton.isEnabled = rootVariables.count > 0
	}
}

extension SidebarVariableController: NSUserInterfaceValidations {

	func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
		guard let action = item.action, let tableView = varTableView else { return false }
		switch action {
			case #selector(SidebarVariableController.copy(_:)):
				return tableView.selectedRowIndexes.count > 0
			case #selector(SidebarVariableController.clearWorkspace(_:)):
				return rootVariables.count > 0
			case #selector(SidebarVariableController.delete(_:)):
				return tableView.selectedRowIndexes.count > 0
			default:
				return false
		}
	}
}

// MARK: - VariableHandler
extension SidebarVariableController: VariableHandler {
	func variableUpdated(_ variable: Variable) {
		if let curVal = variableNamed(variable.name) {
			rootVariables[rootVariables.index(of: curVal)!] = curVal
		} else {
			rootVariables.append(variable)
			rootVariables.sort(by: Variable.compareByName)
		}
		variablesChanged()
	}
	
	func variablesUpdated(_ update: SessionResponse.ListVariablesData) {
		defer { variablesChanged() }
		guard update.delta else {
			rootVariables = Array(update.variables.values)
			return
		}
		for (name, variable) in update.variables {
			if let curVal = variableNamed(name) {
				rootVariables[rootVariables.index(of: curVal)!] = variable
			} else {
				rootVariables.append(variable)
			}
		}
		update.removed.forEach { str in
			if let curVal = variableNamed(str) {
				rootVariables.remove(at: rootVariables.index(of: curVal)!)
			}
		}
	}
}

// MARK: - NSTableViewDataSource
extension SidebarVariableController: NSTableViewDataSource {
	func numberOfRows(in tableView: NSTableView) -> Int {
		return rootVariables.count
	}
	
	func tableView(_ tableView: NSTableView, writeRowsWith rowIndexes: IndexSet, to pboard: NSPasteboard) -> Bool
	{
		guard let row = rowIndexes.first else { return false }
		pboard.clearContents()
		pboard.declareTypes([.variable, .string], owner: nil)
		do {
			let jsonStr = String(data: try session.conInfo.encode(rootVariables[row]), encoding: .utf8)
			// swiftlint:disable:next force_try
			pboard.setString(jsonStr!, forType: .variable)
			pboard.setString(rootVariables[row].description, forType: .string)
		} catch {
			os_log("error converting variable to json: %{public}@", log: .app, error as NSError)
			return false
		}
		return true
	}
}

// MARK: - NSTableViewDelegate
extension SidebarVariableController: NSTableViewDelegate {
	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
	{
		let isValue = tableColumn!.identifier.rawValue == "value"
		let cellIdent = isValue ? "varValueView" : "varNameView"
		// swiftlint:disable:next force_cast
		let view: NSTableCellView = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: cellIdent), owner: self) as! NSTableCellView
		let variable = rootVariables[row]
		view.textField?.stringValue = isValue ? variable.description : variable.name
		if changedIndexes.contains(row) {
			view.textField?.backgroundColor = variableUpdatedBackgroundColor
			view.textField?.drawsBackground = true
		} else {
			view.textField?.backgroundColor = variableNormalBackgroundColor
			view.textField?.drawsBackground = false
		}
		view.textField?.toolTip = isValue ? variable.summary : ""
		return view
	}

	//not sure why this was implemented. don't think we want it now
	func tableView(_ tableView: NSTableView, selectionIndexesForProposedSelection proposedSelectionIndexes: IndexSet) -> IndexSet
	{
//		guard proposedSelectionIndexes.count > 0 else { return proposedSelectionIndexes }
//		let variable = rootVariables[proposedSelectionIndexes.first!]
//		if variable.count <= 1 && variable.primitiveType != .na { return tableView.selectedRowIndexes }
		return proposedSelectionIndexes
	}
	
	func tableViewSelectionDidChange(_ notification: Notification)
	{
		//if no selection, dismiss popover if visible
		guard varTableView.selectedRow >= 0 else {
			if variablePopover?.isShown ?? false { variablePopover?.close(); variablePopover = nil }
			return
		}
	}
}

