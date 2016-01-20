//
//  MacSessionMultiController.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

class MacSessionMultiController: NSViewController, ToolbarItemHandler {
	let LastSelectionKey = "LastSelectionKey"
	
	@IBOutlet var tabView: NSTabView?
	var segmentItem: NSToolbarItem?
	var segmentControl: NSSegmentedControl?
	
	func handlesToolbarItem(item: NSToolbarItem) -> Bool {
		if item.itemIdentifier == "leftView" {
			segmentItem = item
			segmentControl = item.view as! NSSegmentedControl?
			segmentControl?.target = self
			segmentControl?.action = "tabSwitcherClicked:"
			let lastSelection = NSUserDefaults.standardUserDefaults().integerForKey(LastSelectionKey)
			segmentControl?.selectedSegment = lastSelection
			tabView?.selectTabViewItemAtIndex(lastSelection)
			return true
		}
		return false
	}
	
	dynamic func tabSwitcherClicked(sender:AnyObject?) {
		let index = (segmentControl?.selectedSegment)!
		tabView?.selectTabViewItemAtIndex(index)
		NSUserDefaults.standardUserDefaults().setInteger(index, forKey: LastSelectionKey)
	}
}

