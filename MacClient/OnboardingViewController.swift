//
//  OnboardingViewController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import MJLLogger
import Rc2Common
import Networking
import ReactiveSwift
import Model

class OnboardingViewController: NSViewController {
	/// Actions that can be passed to the actionHandler
	///
	/// - open: open the associated workspace
	/// - add: add a new workspace
	/// - remove: remove the associated workspace
	enum UserAction {
		case open(AppWorkspace)
		case add
		case remove(AppWorkspace)
	}
	
	@IBOutlet var textView: NSTextView!
	@IBOutlet var closeButton: NSButton!
	@IBOutlet var addButton: NSButton!
	@IBOutlet var removeButton: NSButton!
	@IBOutlet var wspaceTableView: NSTableView!
	
	var conInfo: ConnectionInfo? { didSet {
		workspaceToken?.dispose()
		project = conInfo?.defaultProject
		workspaceToken = project?.workspaces.signal.observe { [weak self] _ in
			self?.updateWorkspaces()
		}
	} }
	private var workspaceToken: Disposable?
	private var project: AppProject?
	private var didFirstInit: Bool = false
	var actionHandler: ((UserAction) -> Void)?
	
	// MARK: - methods
	override func viewDidLoad() {
		super.viewDidLoad()
		guard let contentFile = Bundle(for: type(of: self)).url(forResource: "OnboardingContent", withExtension: "rtfd")
			else { fatalError("failed to load welcome content") }
		do {
			let str = try NSAttributedString(url: contentFile, options: [:], documentAttributes: nil)
			textView.textStorage?.append(str)
		} catch {
			Log.error("failed to load welcome content: \(error)", .app)
		}
	}
	override func viewWillAppear() {
		super.viewWillAppear()
		wspaceTableView.reloadData()
	}
	
	func updateWorkspaces() {
		DispatchQueue.main.async {
			self.wspaceTableView.reloadData()
		}
//		guard
//			let workspaces = project?.workspaces.value.map( { $0.model }).sorted(by: { (lhs, rhs) -> Bool in return lhs.name < rhs.name }),
	}
	
	@IBAction func closeWindow(_ sender: Any?) {
		view.window?.orderOut(sender)
	}
	
	@IBAction func addWorkspace(_ sender: Any?) {
		actionHandler?(.add)
	}

	@IBAction func removeWorkspace(_ sender: Any?) {
		guard let wspace = project?.workspaces.value[wspaceTableView.selectedRow] else {
			Log.warn("remove workspace called without a selected workspace", .app)
			return
		}
		actionHandler?(.remove(wspace))
	}
	
	@IBAction func openWorkspace(_ sender: Any?) {
		guard let wspace = project?.workspaces.value[wspaceTableView.clickedRow] else { return } //should never happend
		actionHandler?(.open(wspace))
	}
}

extension OnboardingViewController: NSTableViewDataSource {
	func numberOfRows(in tableView: NSTableView) -> Int {
		return project?.workspaces.value.count ?? 0
	}
}

extension OnboardingViewController: NSTableViewDelegate {
	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "wspaceEntry"), owner: self) as? OnboardingCell
		cell?.textField?.stringValue = project?.workspaces.value[row].name ?? "error"
		cell?.lastAccessField?.objectValue = project?.workspaces.value[row].model.lastAccess ?? nil
		return cell
	}
	
	func tableViewSelectionDidChange(_ notification: Notification) {
		removeButton.isEnabled = wspaceTableView.selectedRow >= 0 && (project?.workspaces.value.count ?? 0) > 1
	}
}

// MARK: -

class OnboardingCell: NSTableCellView {
	@IBOutlet var lastAccessField: NSTextField!
	@IBOutlet var dateCreatedField: NSTextField!
}

// MARK: -
class OnboardingWindowController: NSWindowController {
	// swiftlint:disable:next force_cast
	var viewController: OnboardingViewController { return contentViewController as! OnboardingViewController }
}
