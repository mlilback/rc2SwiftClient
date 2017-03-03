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
	
	@IBOutlet var outline: NSOutlineView?
	@IBOutlet var searchField: NSSearchField?
	@IBOutlet var searchMenu: NSMenu?
	let help: HelpController = HelpController.shared
	fileprivate var searchNameOnly: Bool = false
	fileprivate var helpPackages: [TopicWrapper] = []
	fileprivate var expandedBeforeSearch: [TopicWrapper]?
	
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
	@IBAction func search(_ sender:AnyObject) {
		if nil == expandedBeforeSearch {
			let exp = helpPackages.flatMap() { outline!.isItemExpanded($0) ? $0 : nil }
			expandedBeforeSearch = exp
		}
		guard let searchString = searchField?.stringValue, searchString.characters.count > 0 else { resetHelpTopics(); return }
		let results = help.searchTopics(searchString)
		helpPackages = results.map() { TopicWrapper(topic: $0) }
		outline?.reloadData()
		outline!.expandItem(nil, expandChildren: true)
	}
	
	@IBAction func adjustSearchOption(_ menuItem:NSMenuItem) {
		if menuItem.tag == 1 { //name only
			searchNameOnly = !searchNameOnly
			menuItem.state = searchNameOnly ? NSOnState : NSOffState
		}
	}
	
	//MARK: menu delegate
	
	func menuNeedsUpdate(_ menu: NSMenu) {
		if menu == searchMenu {
			if let menuItem = menu.item(withTag: 1) {
				menuItem.state = searchNameOnly ? NSOnState : NSOffState
			}
		}
	}
	
	//MARK: OutlineView Support
	func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
		if let topic = item as? TopicWrapper {
			return topic.children?.count ?? 0
		}
		return helpPackages.count
	}
	
	func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
		if nil == item { return helpPackages[index] }
		return (item as! TopicWrapper).children![index]
	}
	
	func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
		return ((item as! TopicWrapper).children?.count ?? 0) > 0
	}
	
	func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
		return !(item as! TopicWrapper).topic.isPackage
	}
	
	func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
		let cell = outline?.make(withIdentifier: "string", owner: self) as? NSTableCellView
		cell?.textField?.stringValue = (item as! TopicWrapper).topic.name
		return cell
	}
	
	func outlineViewSelectionDidChange(_ notification: Notification) {
		var obj:AnyObject? = nil
		if let topic = outline!.item(atRow: outline!.selectedRow) as? TopicWrapper {
			obj = topic.topic
		}
		NotificationCenter.default.post(name: .DisplayHelpTopic, object:obj, userInfo:nil)
	}
}
