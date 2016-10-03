//
//  BookmarkViewController.swift
//  SwiftClient
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import SwiftyJSON
import os

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
	fileprivate let dateFormatter: DateFormatter = DateFormatter()
	var addController: AddBookmarkViewController?
	var bookmarkManager: BookmarkManager?
	var openSessionCallback:((RestServer) -> Void)?
	fileprivate var appStatus: MacAppStatus?

	var entries: [BookmarkEntry] = []

	override open func viewDidLoad() {
		super.viewDidLoad()
		appStatus = MacAppStatus(windowAccessor: { [unowned self] _ in self.view.window! })
		dateFormatter.dateStyle = .short
		dateFormatter.timeStyle = .short
		tableView?.doubleAction = #selector(BookmarkViewController.openBookmark(_:))
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
		if case .mark(let aMark) = entries[tableView!.selectedRow] {
			var host = ServerHost.localHost
			var password = Constants.LocalServerPassword
			if let bmserver = aMark.server {
				host = bmserver
				password = Keychain().getString(bmserver.keychainKey)!
			}
			let restServer = RestServer(host: host)
			restServer.login(password).onSuccess { loginsession in
				guard let wspace = loginsession.project(withName:aMark.projectName)?.workspace(withName:aMark.workspaceName!) else
				{
					self.appStatus?.presentError(NSError.error(withCode: .noSuchObject, description: nil), session:nil)
					return
				}
				do {
					try restServer.createSession(workspace: wspace, appStatus:self.appStatus!).onSuccess
					{ _ in
						self.openSessionCallback?(restServer)
					}.onFailure { error in
						self.appStatus?.presentError(error, session:nil)
					}
				} catch let innerError {
					os_log("error opening session: %{public}@", type:.error, innerError as NSError)
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
			guard let wspace = loginsession.project(withName:bookmark.projectName)?.workspace(withName:bookmark.workspaceName!) else
			{
				self.presentError(NSError.error(withCode: .noSuchObject, description: nil))
				return
			}
			do {
				try restServer.createSession(workspace: wspace, appStatus: self.appStatus!).onSuccess
				{ _ in
					self.openSessionCallback?(restServer)
					}.onFailure { error in
						self.appStatus?.presentError(error, session:nil)
					}
			} catch let outerError {
				os_log("error opening session: %{public}@", type:.error, outerError as NSError)
				self.appStatus?.presentError(outerError as NSError, session: nil)
			}
		
		}.onFailure { error in
			self.appStatus?.presentError(error, session:nil)
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
	
	func displayError(_ error:NSError) {
		appStatus?.presentError(error, session: nil)
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
