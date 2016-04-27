//
// SidebarHelpController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

class TopicWrapper: NSObject {
	var topic:HelpTopic
	var children:[TopicWrapper]?
	init(topic:HelpTopic) {
		self.topic = topic
		self.children = topic.subtopics?.map() { (t) -> TopicWrapper in TopicWrapper(topic:t) }
		super.init()
	}
}

class SidebarHelpController : AbstractSessionViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
	
	@IBOutlet var outline:NSOutlineView?
	@IBOutlet var searchField: NSSearchField?
	@IBOutlet var searchMenu: NSMenu?
	let help:HelpController = HelpController.sharedInstance
	private var searchNameOnly:Bool = false
	private var helpPackages:[TopicWrapper] = []
	private var expandedBeforeSearch:[TopicWrapper]?
	
	//MARK: lifecycle
	override func  viewDidLoad() {
		super.viewDidLoad()
		resetHelpTopics()
	}

	func resetHelpTopics() {
		helpPackages = help.packages.map() { TopicWrapper(topic: $0) }
		outline?.reloadData()
		if let toExpand = expandedBeforeSearch {
			toExpand.forEach() { outline!.expandItem($0) }
		}
		expandedBeforeSearch = nil
	}
	
	//MARK: actions
	@IBAction func search(sender:AnyObject) {
		if nil == expandedBeforeSearch {
			let exp = helpPackages.flatMap() { outline!.isItemExpanded($0) ? $0 : nil }
			expandedBeforeSearch = exp
		}
		guard searchField?.stringValue.characters.count > 0 else { resetHelpTopics(); return }
		let results = help.searchTopics(searchField!.stringValue)
		helpPackages = results.map() { TopicWrapper(topic: $0) }
		outline?.reloadData()
		outline!.expandItem(nil, expandChildren: true)
	}
	
	@IBAction func adjustSearchOption(menuItem:NSMenuItem) {
		if menuItem.tag == 1 { //name only
			searchNameOnly = !searchNameOnly
			menuItem.state = searchNameOnly ? NSOnState : NSOffState
		}
	}
	
	//MARK: menu delegate
	
	func menuNeedsUpdate(menu: NSMenu) {
		if menu == searchMenu {
			if let menuItem = menu.itemWithTag(1) {
				menuItem.state = searchNameOnly ? NSOnState : NSOffState
			}
		}
	}
	
	//MARK: OutlineView Support
	func outlineView(outlineView: NSOutlineView, numberOfChildrenOfItem item: AnyObject?) -> Int {
		if let topic = item as? TopicWrapper {
			return topic.children?.count ?? 0
		}
		return helpPackages.count
	}
	
	func outlineView(outlineView: NSOutlineView, child index: Int, ofItem item: AnyObject?) -> AnyObject {
		if nil === item { return helpPackages[index] }
		return (item as! TopicWrapper).children![index]
	}
	
	func outlineView(outlineView: NSOutlineView, isItemExpandable item: AnyObject) -> Bool {
		return ((item as! TopicWrapper).children?.count ?? 0) > 0
	}
	
	func outlineView(outlineView: NSOutlineView, shouldSelectItem item: AnyObject) -> Bool {
		return !(item as! TopicWrapper).topic.isPackage
	}
	
	func outlineView(outlineView: NSOutlineView, viewForTableColumn tableColumn: NSTableColumn?, item: AnyObject) -> NSView? {
		let cell = outline?.makeViewWithIdentifier("string", owner: self) as? NSTableCellView
		cell?.textField?.stringValue = (item as! TopicWrapper).topic.name
		return cell
	}
	
	func outlineViewSelectionDidChange(notification: NSNotification) {
		var obj:AnyObject? = nil
		if let topic = outline!.itemAtRow(outline!.selectedRow) as? TopicWrapper {
			obj = topic.topic
		}
		NSNotificationCenter.defaultCenter().postNotificationName(DisplayHelpTopicNotification, object:obj, userInfo:nil)
	}
}
