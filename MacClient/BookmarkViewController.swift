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
	
	var entries: [BookmarkEntry] = []
	
	override public func viewDidLoad() {
		super.viewDidLoad()
		dateFormatter.dateStyle = .ShortStyle
		dateFormatter.timeStyle = .ShortStyle
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
		dispatch_async(dispatch_get_main_queue()) {
			self.presentViewControllerAsSheet(self.addController!)
		}
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
