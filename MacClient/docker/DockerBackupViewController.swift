//
//  DockerBackupViewController.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import ReactiveSwift
import MJLLogger
import Docker
import ClientCore

class DockerBackupViewController: DockerManagerInjectable {
	@IBOutlet var backupTableView: NSTableView!
	@IBOutlet var backupButton: NSButton!
	@IBOutlet var restoreButton: NSButton!
	@IBOutlet private var progressStackView: NSStackView!
	@IBOutlet private var progressView: NSProgressIndicator!
	
	@objc private dynamic var isRestoring: Bool = false
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
		backupManager?.performBackup().observe(on: UIScheduler()).startWithResult() { result in
			guard let err = result.error else { return } //worked
			self.presentError(err)
		}
	}
	
	@IBAction func performRestore(_ sender: AnyObject?) {
		let selRow = backupTableView.selectedRow
		guard selRow >= 0 else { return }
		let targetBackup = backups[selRow]
		isRestoring = true
		DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
		self.backupManager?.restore(backup: targetBackup).observe(on: UIScheduler()).startWithResult { result in
			self.isRestoring = false
			guard result.error == nil else {
				self.presentError(result.error!, modalFor: self.view.window!, delegate: nil, didPresent: nil, contextInfo: nil)
				return
			}
		}
		}
	}
	
	override func willPresentError(_ error: Error) -> Error {
		guard let rerror = error as? Rc2Error, let derror = rerror.nestedError as? DockerError else { return error }
		let reason = derror.localizedDescription
		let nerror = NSError(domain: rc2ErrorDomain, code: 0, userInfo: [NSUnderlyingErrorKey: derror, NSLocalizedDescriptionKey: "backup restore failed", NSLocalizedRecoverySuggestionErrorKey: reason, NSLocalizedFailureReasonErrorKey: reason])
		return nerror
	}
	
	@objc func delete(_ sender: Any?) {
		let selRow = backupTableView.selectedRow
		guard selRow >= 0 else { return }
		let targetBackup = backups[selRow]
		do {
			try FileManager.default.removeItem(at: targetBackup.url)
		} catch {
			Log.warn("error removing backup: \(error)", .app)
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
		let view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "backup"), owner: nil) as? NSTableCellView
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
