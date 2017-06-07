//
//  DockerBackupViewController.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import ReactiveSwift
import os

class DockerBackupViewController: DockerManagerInjectable {
	@IBOutlet var backupTableView: NSTableView!
	@IBOutlet var backupButton: NSButton!
	@IBOutlet var restoreButton: NSButton!
	fileprivate var backups: [DockerBackup] = []
	var backupManager: DockerBackupManager?
	
	override func viewDidLoad() {
		super.viewDidLoad()
		restoreButton.isEnabled = false
		backupManager?.backupSignal.observe(on: UIScheduler()).observeValues { [weak self] newBackup in
			guard let me = self else { return }
			me.backups.append(newBackup)
			me.backupTableView.insertRows(at: IndexSet(integer: me.backups.count - 1), withAnimation: [])
		}
		backups = backupManager?.backups ?? []
	}
	
	override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		if menuItem.action == #selector(delete(_:)) {
			return backupTableView.selectedRow >= 0
		}
		return super.validateMenuItem(menuItem)
	}
	
	override func keyDown(with event: NSEvent) {
		interpretKeyEvents([event])
	}
	
	@IBAction func performBackup(_ sender: AnyObject?) {
		backupManager?.performBackup().start()
	}
	
	@IBAction func performRestore(_ sender: AnyObject?) {
		//TODO: implement restore
	}
	
	func delete(_ sender: Any?) {
		let selRow = backupTableView.selectedRow
		guard selRow >= 0 else { return }
		let targetBackup = backups[selRow]
		do {
			try FileManager.default.removeItem(at: targetBackup.url)
		} catch {
			os_log("error removing backup: %{public}@", log: .app, error.localizedDescription)
			NSBeep()
			return
		}
		backups.remove(at: selRow)
		backupTableView.removeRows(at: [selRow], withAnimation: [])
	}
	
	override func deleteBackward(_ sender: Any?) {
		delete(sender)
	}
}

extension DockerBackupViewController: NSTableViewDataSource {
	func numberOfRows(in tableView: NSTableView) -> Int {
		return backups.count
	}
	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		let view = tableView.make(withIdentifier: "backup", owner: nil) as? NSTableCellView
		view?.objectValue = backups[row]
		view?.textField?.objectValue = backups[row].date
		return view
	}
}

extension DockerBackupViewController: NSTableViewDelegate {
	func tableViewSelectionDidChange(_ notification: Notification) {
		restoreButton.isEnabled = backupTableView.selectedRow >= 0
	}
}
