//
//  DockerContainerController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import ClientCore
import ReactiveSwift

public class DockerContainerController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
	@IBOutlet dynamic var containerTable: NSTableView?
	dynamic var selection: NSIndexSet?
	var selectedContainer = MutableProperty<DockerContainer?>(nil)
	var manager: DockerManager? { didSet {
		containerTable?.reloadData()
		for container in (manager?.containers ?? []) {
			container.state.signal.observeValues { [weak self] _ in
				DispatchQueue.main.async {
					self?.containerTable?.reloadData()
					self?.selectedContainer.value = nil
				}
			}
		}
	} }
	//should probably coalesce reloads so if all are changed in on fell swoop, we don't make 3 calls to reload
	
//	public var selectedContainer:DockerContainer? {
//		guard let row = containerTable?.selectedRow else { return nil }
//		guard row >= 0 && row < (manager?.containers.count ?? 0) else { return nil }
//		return manager?.containers[row]
//	}
	
	public func numberOfRows(in tableView: NSTableView) -> Int {
		return manager?.containers.count ?? 0
	}
	
	public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		let cell = tableView.make(withIdentifier: "dockerCell", owner: nil) as? NSTableCellView
		switch tableColumn!.identifier {
			case "state":
				cell?.textField?.stringValue = manager?.containers[row].state.value.rawValue ?? ""
			default:
				cell?.textField?.stringValue = manager?.containers[row].name ?? ""
		}
		return cell
	}
	
	public func tableViewSelectionDidChange(_ notification: Notification) {
		guard let row = containerTable?.selectedRow, row >= 0 && row < (manager?.containers.count ?? 0) else {
			selectedContainer.value = nil
			return
		}
		selectedContainer.value = manager!.containers[row]
	}
}
