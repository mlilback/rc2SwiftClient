//
// SidebarHelpController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import SwiftyUserDefaults

class TopicWrapper: NSObject {
	var topic: HelpTopic
	var children: [TopicWrapper]?
	init(topic: HelpTopic) {
		self.topic = topic
		self.children = topic.subtopics?.map { (t) -> TopicWrapper in TopicWrapper(topic:t) }
		super.init()
	}
}

class SidebarHelpController: AbstractSessionViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate, NSSearchFieldDelegate
{
	
	@IBOutlet var outline: NSOutlineView?
	@IBOutlet var searchField: NSSearchField?
	@IBOutlet var searchMenu: NSMenu?
	let help: HelpController = HelpController.shared
	fileprivate var fullContentSearch: Bool = false
	fileprivate var helpPackages: [TopicWrapper] = []
	fileprivate var expandedBeforeSearch: [TopicWrapper]?
	
	// MARK: lifecycle
	override func  viewDidLoad() {
		super.viewDidLoad()
		searchField?.delegate = self
		resetHelpTopics()
		searchField?.sendsWholeSearchString = false
		searchField?.sendsSearchStringImmediately = false
		fullContentSearch = UserDefaults.standard[.helpTopicSearchSummaries]
	}

	override func validateMenuItem(_ item: NSMenuItem) -> Bool {
		guard item.action == #selector(adjustSearchOption(_:)) else { return super.validateMenuItem(item) }
		switch item.tag {
		case 1:
			item.state = fullContentSearch ? .off : .on
		case 2:
			item.state = fullContentSearch ? .on : .off
		default:
			break
		}
		return true
	}
	
	func resetHelpTopics() {
		helpPackages = help.packages.map { TopicWrapper(topic: $0) }
		outline?.reloadData()
		if let toExpand = expandedBeforeSearch {
			toExpand.forEach { outline!.expandItem($0) }
		}
		expandedBeforeSearch = nil
	}
	
	// MARK: actions
	@IBAction func search(_ sender: AnyObject) {
		guard let searchString = searchField?.stringValue, searchString.characters.count > 0 else { resetHelpTopics(); return }
		let results = fullContentSearch ? help.searchTopics(searchString) : help.searchTitles(searchString)
		helpPackages = results.map { TopicWrapper(topic: $0) }
		outline?.reloadData()
		outline!.expandItem(nil, expandChildren: true)
	}
	
	@IBAction func adjustSearchOption(_ menuItem: NSMenuItem) {
		fullContentSearch = menuItem.tag == 2
		UserDefaults.standard[.helpTopicSearchSummaries] = fullContentSearch
		if !searchField!.stringValue.characters.isEmpty {
			search(menuItem)
		}
	}
	
	// MARK: search field delegate
	func searchFieldDidStartSearching(_ sender: NSSearchField) {
		if nil == expandedBeforeSearch {
			let exp = helpPackages.flatMap { outline!.isItemExpanded($0) ? $0 : nil }
			expandedBeforeSearch = exp
		}
	}
	
	func searchFieldDidEndSearching(_ sender: NSSearchField) {
		resetHelpTopics()
	}
	
	// MARK: OutlineView Support
	func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
		if let topic = item as? TopicWrapper {
			return topic.children?.count ?? 0
		}
		return helpPackages.count
	}
	
	func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
		if nil == item { return helpPackages[index] }
		return (item as! TopicWrapper).children![index] // swiftlint:disable:this force_cast
	}
	
	func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
		return ((item as! TopicWrapper).children?.count ?? 0) > 0 // swiftlint:disable:this force_cast
	}
	
	func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
		return !(item as! TopicWrapper).topic.isPackage // swiftlint:disable:this force_cast
	}
	
	func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
		let cell = outline?.makeView(withIdentifier: NSUserInterfaceItemIdentifier("string"), owner: self) as? NSTableCellView
		cell?.textField?.stringValue = (item as! TopicWrapper).topic.name // swiftlint:disable:this force_cast
		return cell
	}
	
	func outlineViewSelectionDidChange(_ notification: Notification) {
		var obj: AnyObject? = nil
		if let topic = outline!.item(atRow: outline!.selectedRow) as? TopicWrapper {
			obj = topic.topic
		}
		NotificationCenter.default.post(name: .DisplayHelpTopic, object:obj, userInfo:nil)
	}
}
