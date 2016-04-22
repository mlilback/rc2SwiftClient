//
// SidebarHelpController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa


class SidebarHelpController : AbstractSessionViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
	@IBOutlet var outline:NSOutlineView?
	let help:HelpController = HelpController.sharedInstance
	
	override func  viewDidLoad() {
		super.viewDidLoad()
	}

	func outlineView(outlineView: NSOutlineView, numberOfChildrenOfItem item: AnyObject?) -> Int {
		if let topic = item as? HelpTopic {
			return topic.subtopics?.count ?? 0
		}
		return help.packages.count
	}
	
	func outlineView(outlineView: NSOutlineView, child index: Int, ofItem item: AnyObject?) -> AnyObject {
		if nil === item { return help.packages[index] }
		return (item as! HelpTopic).subtopics![index]
	}
	
	func outlineView(outlineView: NSOutlineView, isItemExpandable item: AnyObject) -> Bool {
		return ((item as! HelpTopic).subtopics?.count ?? 0) > 0
	}
	
	func outlineView(outlineView: NSOutlineView, shouldSelectItem item: AnyObject) -> Bool {
		return !(item as! HelpTopic).isPackage
	}
	
	func outlineView(outlineView: NSOutlineView, viewForTableColumn tableColumn: NSTableColumn?, item: AnyObject) -> NSView? {
		let cell = outline?.makeViewWithIdentifier("string", owner: self) as? NSTableCellView
		cell?.textField?.stringValue = (item as! HelpTopic).name
		return cell
	}
	
	func outlineViewSelectionDidChange(notification: NSNotification) {
		let topic = outline!.itemAtRow(outline!.selectedRow) as? HelpTopic
		NSNotificationCenter.defaultCenter().postNotificationName(DisplayHelpTopicNotification, object:topic, userInfo:nil)
	}
}
