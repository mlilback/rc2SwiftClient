//
//  BookmarkViewController.swift
//  SwiftClient
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import SwiftyJSON

enum BookmarkEntry {
	case Group(String)
	case Mark(Bookmark)
}

public class BookmarkViewController: NSViewController {
	@IBOutlet var tableView:NSTableView?
	@IBOutlet var addRemoveButtons: NSSegmentedControl?
	private let dateFormatter: NSDateFormatter = NSDateFormatter()
	var addController: AddBookmarkViewController?
	var bookmarkManager: BookmarkManager?
	var openSessionCallback:((RestServer) -> Void)?
	private var appStatus: MacAppStatus?

	var entries: [BookmarkEntry] = []

	override public func viewDidLoad() {
		super.viewDidLoad()
		appStatus = MacAppStatus(windowAccessor: { [unowned self] _ in self.view.window! })
		dateFormatter.dateStyle = .ShortStyle
		dateFormatter.timeStyle = .ShortStyle
		tableView?.doubleAction = #selector(BookmarkViewController.openBookmark(_:))
	}
	
	override public func viewWillAppear() {
		super.viewWillAppear()
		loadBookmarkEntries()
		tableView?.reloadData()
	}
	
	func loadBookmarkEntries() {
		//turn into entries
		entries.removeAll()
		for aGroup in bookmarkManager!.bookmarkGroups.values.sort({ (g1, g2) in g1.key < g2.key }) {
			entries.append(BookmarkEntry.Group(aGroup.key))
			for aMark in aGroup.bookmarks.sort({ (b1, b2) in b1.name < b2.name }) {
				entries.append(BookmarkEntry.Mark(aMark))
			}
		}
	}
	
	@IBAction func addRemoveBookmark(sender:AnyObject?) {
		if addRemoveButtons?.selectedSegment == 0 {
			addBookmark(sender)
		} else {
			removeBookmark(sender)
		}
	}

	@IBAction func removeBookmark(sender:AnyObject?) {
		
	}
	
	@IBAction func addBookmark(sender:AnyObject?) {
		addController = storyboard?.instantiateControllerWithIdentifier("addBookmark") as? AddBookmarkViewController
		addController?.bookmarkAddedClosure = { (host, pw) in
			let bookmark = Bookmark(name: "untitled", server: host, project: pw.project, workspace: pw.workspace)
			self.bookmarkManager?.addBookmark(bookmark)
			self.bookmarkManager?.save()
			self.loadBookmarkEntries()
			self.tableView?.reloadData()
			let idx = self.entryIndexForBookmark(bookmark)!
			self.tableView?.selectRowIndexes(NSIndexSet(index:idx), byExtendingSelection: false)
			self.dismissViewController(self.addController!)
			dispatch_async(dispatch_get_main_queue()) {
				//start editing of name
				if let cellView = self.tableView?.viewAtColumn(0, row: idx, makeIfNecessary: true) as? NSTableCellView
				{
					cellView.window!.makeFirstResponder(cellView.textField)
				}
			}
		}
		dispatch_async(dispatch_get_main_queue()) {
			self.presentViewControllerAsSheet(self.addController!)
		}
	}
	
	@IBAction func bookmarkNameEditedAction(textField:NSTextField)
	{
		assert(tableView!.selectedRow >= 0)
		if case .Mark(let aMark) = entries[tableView!.selectedRow] {
			let nbmark = aMark.withChangedName(textField.stringValue)
			bookmarkManager!.replaceBookmark(aMark, with:nbmark)
			bookmarkManager!.save()
		}
	}
	
	@IBAction func openBookmark(sender:AnyObject?) {
		if case .Mark(let aMark) = entries[tableView!.selectedRow] {
			var host = ServerHost.localHost
			var password = Constants.LocalServerPassword
			if let bmserver = aMark.server {
				host = bmserver
				password = Keychain().getString(bmserver.keychainKey)!
			}
			let restServer = RestServer(host: host)
			restServer.login(password).onSuccess { loginsession in
				guard let wspace = loginsession.projectWithName(aMark.projectName)?.workspaceWithName(aMark.workspaceName!) else
				{
					self.appStatus?.presentError(NSError.error(withCode: .NoSuchProject, description: nil), session:nil)
					return
				}
				restServer.createSession(wspace).onSuccess { _ in
					self.openSessionCallback?(restServer)
				}.onFailure { error in
					self.appStatus?.presentError(error, session:nil)
				}
			}.onFailure { error in
				self.appStatus?.presentError(error, session:nil)
			}
		}
	}
	
	func openSession(withBookmark bookmark:Bookmark, password:String?) {
		var host = ServerHost.localHost
		var pass = Constants.LocalServerPassword
		if let bmserver = bookmark.server {
			host = bmserver
			if nil == password {
				pass = Keychain().getString(bmserver.keychainKey)!
			} else {
				pass = password!
			}
		}
		let restServer = RestServer(host: host)
		restServer.login(pass).onSuccess { loginsession in
		guard let wspace = loginsession.projectWithName(bookmark.projectName)?.workspaceWithName(bookmark.workspaceName!) else
		{
			self.presentError(NSError.error(withCode: .NoSuchProject, description: nil))
			return
		}
		restServer.createSession(wspace).onSuccess { _ in
			self.openSessionCallback?(restServer)
			}.onFailure { error in
				self.appStatus?.presentError(error, session:nil)
		}
		}.onFailure { error in
			self.appStatus?.presentError(error, session:nil)
		}
	}

	func entryIndexForBookmark(bmark:Bookmark) -> Int? {
		for idx in 0..<entries.count {
			if case .Mark(let aMark) = entries[idx] where aMark == bmark {
				return idx
			}
		}
		return nil
	}
	
	func displayError(error:NSError) {
		appStatus?.presentError(error, session: nil)
	}
}

extension BookmarkViewController: NSTableViewDataSource {
	public func numberOfRowsInTableView(tableView: NSTableView) -> Int {
		return entries.count
	}
}

extension BookmarkViewController: NSTableViewDelegate {
	public func tableView(tableView: NSTableView, viewForTableColumn tableColumn: NSTableColumn?, row: Int) -> NSView? {
		var str = ""
		switch(entries[row]) {
			case .Group(let name):
				str = name
			case .Mark(let mark):
				switch(tableColumn!.identifier) {
					case "name":
						str = mark.name
					case "lastUsed":
						if mark.lastUsed < 1 {
							str = ""
						} else {
							str = dateFormatter.stringFromDate(NSDate(timeIntervalSinceReferenceDate: mark.lastUsed))
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
		let cellView = tableView.makeViewWithIdentifier("name", owner: nil) as! NSTableCellView
		cellView.textField?.stringValue = str
		return cellView
	}
	
	public func tableView(tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
		switch(entries[row]) {
			case .Group(_):
				return false
			case .Mark(_):
				return true
		}
	}
	
	public func tableView(tableView: NSTableView, isGroupRow row: Int) -> Bool {
		switch(entries[row]) {
			case .Group(_):
				return true
			case .Mark(_):
				return false
		}
	}
	
	public func tableViewSelectionDidChange(notification: NSNotification) {
		let noSelection = tableView!.selectedRow == -1
		addRemoveButtons?.setEnabled(!noSelection && entries.count > 2, forSegment: 1) //1 bookmark + 1 group row
	}
}

extension BookmarkViewController: NSTextFieldDelegate {
	public func control(control: NSControl, textShouldEndEditing fieldEditor: NSText) -> Bool {
		return fieldEditor.string?.characters.count > 0
	}
}
