//
//  BookmarkViewController.swift
//  SwiftClient
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import os
import Networking
import ReactiveSwift
import Result
import ClientCore

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

fileprivate func > <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l > r
  default:
    return rhs < lhs
  }
}


enum BookmarkEntry {
	case group(String)
	case mark(Bookmark)
}

open class BookmarkViewController: NSViewController {
	@IBOutlet var tableView:NSTableView?
	@IBOutlet var addRemoveButtons: NSSegmentedControl?
	@IBOutlet var progressContainer: NSView?
	@IBOutlet var progressSpinner: NSProgressIndicator?
	@IBOutlet var progressLabel: NSTextField?
	fileprivate let dateFormatter: DateFormatter = DateFormatter()
	var addController: AddBookmarkViewController?
	var bookmarkManager: BookmarkManager?
	var openSessionCallback:((Session) -> Void)?
	fileprivate var appStatus: MacAppStatus?
	fileprivate var openInProgress: Bool = false

	var entries: [BookmarkEntry] = []

	func windowAccessor(session: Session?) -> NSWindow {
		guard let win = self.view.window else {
			os_log("bookmark appstatus has no window", log: .app, type: .error)
			fatalError()
		}
		return win
	}
	override open func viewDidLoad() {
		super.viewDidLoad()
		appStatus = MacAppStatus(windowAccessor: windowAccessor)
		dateFormatter.dateStyle = .short
		dateFormatter.timeStyle = .short
		tableView?.doubleAction = #selector(BookmarkViewController.openBookmark(_:))
		progressContainer?.isHidden = true
	}
	
	override open func viewWillAppear() {
		super.viewWillAppear()
		loadBookmarkEntries()
		tableView?.reloadData()
	}
	
	func loadBookmarkEntries() {
		//turn into entries
		entries.removeAll()
		for aGroup in bookmarkManager!.bookmarkGroups.values.sorted(by: { (g1, g2) in g1.key < g2.key }) {
			entries.append(BookmarkEntry.group(aGroup.key))
			for aMark in aGroup.bookmarks.sorted(by: { (b1, b2) in b1.name < b2.name }) {
				entries.append(BookmarkEntry.mark(aMark))
			}
		}
	}
	
	@IBAction func addRemoveBookmark(_ sender:AnyObject?) {
		if addRemoveButtons?.selectedSegment == 0 {
			addBookmark(sender)
		} else {
			removeBookmark(sender)
		}
	}

	@IBAction func removeBookmark(_ sender:AnyObject?) {
		
	}
	
	@IBAction func addBookmark(_ sender:AnyObject?) {
		addController = storyboard?.instantiateController(withIdentifier: "addBookmark") as? AddBookmarkViewController
		addController?.bookmarkAddedClosure = { (host, pw) in
			let bookmark = Bookmark(name: "untitled", server: host, project: pw.project, workspace: pw.workspace)
			self.bookmarkManager?.addBookmark(bookmark)
			self.bookmarkManager?.save()
			self.loadBookmarkEntries()
			self.tableView?.reloadData()
			let idx = self.entryIndexForBookmark(bookmark)!
			self.tableView?.selectRowIndexes(IndexSet(integer:idx), byExtendingSelection: false)
			self.dismissViewController(self.addController!)
			DispatchQueue.main.async {
				//start editing of name
				if let cellView = self.tableView?.view(atColumn: 0, row: idx, makeIfNecessary: true) as? NSTableCellView
				{
					cellView.window!.makeFirstResponder(cellView.textField)
				}
			}
		}
		DispatchQueue.main.async {
			self.presentViewControllerAsSheet(self.addController!)
		}
	}
	
	@IBAction func bookmarkNameEditedAction(_ textField:NSTextField)
	{
		assert(tableView!.selectedRow >= 0)
		if case .mark(let aMark) = entries[tableView!.selectedRow] {
			let nbmark = aMark.withChangedName(textField.stringValue)
			bookmarkManager!.replaceBookmark(aMark, with:nbmark)
			bookmarkManager!.save()
		}
	}
	
	@IBAction func openBookmark(_ sender:AnyObject?) {
		//if double click where there is no row, selectedRow is -1
		guard tableView!.selectedRow >= 0 else { return }
		guard !openInProgress else { return }
		if case .mark(let aMark) = entries[tableView!.selectedRow] {
			openSession(withBookmark: aMark, password: nil)
		}
	}
	
	func openSession(withBookmark bookmark:Bookmark, password:String?) {
		var host = ServerHost.localHost
		var pass = NetworkConstants.localServerPassword
		if let bmserver = bookmark.server {
			host = bmserver
			if nil == password {
				pass = Keychain().getString(bmserver.keychainKey)!
			} else {
				pass = password!
			}
		}
		openInProgress = true
		let loginFactory = LoginFactory()
		loginFactory.login(to: host, as: host.user, password: pass).observe(on: UIScheduler()).startWithResult { (result) in
			self.handleLogin(bookmark: bookmark, result: result)
		}
	}

	/// Takes action with the result from an attempt to login
	///
	/// - Parameters:
	///   - bookmark: the bookmark to connect to
	///   - result: the result from a LoginFactory
	open func handleLogin(bookmark: Bookmark, result: Result<ConnectionInfo, Rc2Error>) {
		guard let conInfo = result.value else {
			self.appStatus?.presentError(result.error!, session: nil)
			return
		}
		guard let wspace = conInfo.project(withName: bookmark.projectName)?.workspace(withName: bookmark.workspaceName!) else
		{
			let desc = String.localizedStringWithFormat(NSLocalizedString("Failed to find workspace %@", comment: ""), bookmark.workspaceName!)
			self.appStatus?.presentError(Rc2Error(type: .noSuchElement, explanation: desc), session:nil)
			return
		}
		let session = Session(connectionInfo: conInfo, workspace: wspace)
		session.open().observe(on: UIScheduler()).on(starting: { 
			self.progressContainer?.isHidden = false
			self.progressSpinner?.startAnimation(self)
			self.progressLabel?.stringValue = "Connecting to \(conInfo.host.name)…"
		}, terminated: {
			self.progressSpinner?.stopAnimation(self)
			self.progressContainer?.isHidden = true
			self.openInProgress = false
		}).start { event in
			switch event {
			case .completed:
				self.openSessionCallback?(session)
			case .failed(let err):
				os_log("failed to open websocket: %{public}s", log: .session, err.localizedDescription)
				fatalError()
			case .value: //(let _):
				// do nothing as using indeterminate progress
				break
			case .interrupted:
				break //should never happen
			}
		}
	}
	
	func entryIndexForBookmark(_ bmark:Bookmark) -> Int? {
		for idx in 0..<entries.count {
			if case .mark(let aMark) = entries[idx] , aMark == bmark {
				return idx
			}
		}
		return nil
	}
}

extension BookmarkViewController: NSTableViewDataSource {
	public func numberOfRows(in tableView: NSTableView) -> Int {
		return entries.count
	}
}

extension BookmarkViewController: NSTableViewDelegate {
	public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		var str = ""
		switch(entries[row]) {
			case .group(let name):
				str = name
			case .mark(let mark):
				switch(tableColumn!.identifier) {
					case "name":
						str = mark.name
					case "lastUsed":
						if mark.lastUsed < 1 {
							str = ""
						} else {
							str = dateFormatter.string(from: Date(timeIntervalSinceReferenceDate: mark.lastUsed))
						}
					case "project":
						str = mark.projectName
					case "workspace":
						str = mark.workspaceName ?? ""
					case "projwspace":
						str = "\(mark.projectName)\(mark.workspaceName?.characters.count > 0 ? "/\(mark.workspaceName!)" : "")"
					default:
						str = ""
				}
		}
		let cellView = tableView.make(withIdentifier: "name", owner: nil) as! NSTableCellView
		cellView.textField?.stringValue = str
		return cellView
	}
	
	public func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
		switch(entries[row]) {
			case .group(_):
				return false
			case .mark(_):
				return true
		}
	}
	
	public func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
		switch(entries[row]) {
			case .group(_):
				return true
			case .mark(_):
				return false
		}
	}
	
	public func tableViewSelectionDidChange(_ notification: Notification) {
		let noSelection = tableView!.selectedRow == -1
		addRemoveButtons?.setEnabled(!noSelection && entries.count > 2, forSegment: 1) //1 bookmark + 1 group row
	}
}

extension BookmarkViewController: NSTextFieldDelegate {
	public func control(_ control: NSControl, textShouldEndEditing fieldEditor: NSText) -> Bool {
		return fieldEditor.string?.characters.count > 0
	}
}
