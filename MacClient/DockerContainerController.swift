//
//  DockerContainerController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import ClientCore

public class DockerContainerController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
	@IBOutlet dynamic var containerTable: NSTableView?
	dynamic var selection: NSIndexSet?
	var manager: DockerManager? { didSet {
		containerTable?.reloadData()
	} }
	
	public func numberOfRows(in tableView: NSTableView) -> Int {
		return manager?.containers.count ?? 0
	}
	
	public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		let cell = tableView.make(withIdentifier: "dockerCell", owner: nil) as? NSTableCellView
		switch tableColumn!.identifier {
			case "state":
				cell?.textField?.stringValue = manager?.containers[row].state.rawValue ?? ""
			default:
				cell?.textField?.stringValue = manager?.containers[row].name ?? ""
		}
		return cell
	}
}
