//
//  BookmarkViewController.swift
//  SwiftClient
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import SwiftyJSON

struct BookmarkGroup {
	let key:String
	var bookmarks:[Bookmark] = []
	
	init(key:String, firstBookmark:Bookmark? = nil) {
		self.key = key
		if firstBookmark != nil { bookmarks.append(firstBookmark!) }
	}
	
	init(original:BookmarkGroup) {
		self.key = original.key
		self.bookmarks = original.bookmarks
	}
	
	func addBookmark(bmark:Bookmark) -> BookmarkGroup {
		return BookmarkGroup(original: self).addBookmark(bmark)
	}
}

enum BookmarkEntry {
	case Group(String)
	case Mark(Bookmark)
}

//MARK: -
public class BookmarkViewController: NSViewController {
	@IBOutlet var tableView:NSTableView?
	@IBOutlet var addRemoveButtons: NSSegmentedControl?
	private let dateFormatter: NSDateFormatter = NSDateFormatter()
	let localName = NSLocalizedString("Local Server", comment: "")
	var addController: AddBookmarkViewController?
	
	var entries: [BookmarkEntry] = []
	var existingHosts: [ServerHost] = []
	
	override public func viewDidLoad() {
		super.viewDidLoad()
		loadBookmarks()
		tableView?.reloadData()
		dateFormatter.dateStyle = .ShortStyle
		dateFormatter.timeStyle = .ShortStyle
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
		addController?.existingHosts = existingHosts
		dispatch_async(dispatch_get_main_queue()) {
			self.presentViewControllerAsSheet(self.addController!)
		}
	}
	
	func loadBookmarks() {
		var groups = [String:BookmarkGroup]()
		let defaults = NSUserDefaults.standardUserDefaults()
		var bmarks = [Bookmark]()
		//load them, or create default ones
		if let bmstr = defaults.stringForKey(PrefKeys.Bookmarks) {
			bmarks = Bookmark.bookmarksFromJsonArray(JSON.parse(bmstr).arrayValue)
		}
		if bmarks.count < 1 {
			bmarks = createDefaultBookmarks()
		}
		//group them
		for aMark in bmarks {
			if let grp = groups[aMark.server?.host ?? "local"] {
				groups[grp.key] = grp.addBookmark(aMark)
			} else {
				groups["local"] = BookmarkGroup(key: aMark.server == nil ? localName : aMark.server!.name, firstBookmark: aMark)
			}
		}
		//turn into entries
		entries.removeAll()
		for aGroup in groups.values.sort({ (g1, g2) in g1.key < g2.key }) {
			entries.append(BookmarkEntry.Group(aGroup.key))
			for aMark in aGroup.bookmarks.sort({ (b1, b2) in b1.name < b2.name }) {
				entries.append(BookmarkEntry.Mark(aMark))
			}
		}
		
		//add hosts
		var hostSet = Set<ServerHost>()
		for aMark in bmarks {
			if aMark.server != nil { hostSet.insert(aMark.server!) }
		}
		existingHosts.appendContentsOf(hostSet)
		existingHosts.sortInPlace() { $0.name < $1.name }
	}
	
	func createDefaultBookmarks() -> [Bookmark] {
		let bmark = Bookmark(name:"starter", server: nil, project: "default", workspace: "default")
		return [bmark]
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
