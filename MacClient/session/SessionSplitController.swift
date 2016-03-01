//
//  SessionSplitController
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

let LastSelectedSessionTabIndex = "LastSelectedSessionTabIndex"
let SidebarFixedWidth: CGFloat = 209

class SessionSplitController: NSSplitViewController, ToolbarItemHandler {
	var segmentItem: NSToolbarItem?
	var segmentControl: NSSegmentedControl?

	override func awakeFromNib() {
		super.awakeFromNib()
		let splitItem = splitViewItems[0]
		splitItem.minimumThickness = SidebarFixedWidth
		splitItem.maximumThickness = SidebarFixedWidth
	}
	
	func handlesToolbarItem(item: NSToolbarItem) -> Bool {
		if item.itemIdentifier == "leftView" {
			segmentItem = item
			segmentControl = item.view as! NSSegmentedControl?
			segmentControl?.target = self
			segmentControl?.action = "tabSwitcherClicked:"
			let sidebar = sidebarTabController()
			let lastSelection = NSUserDefaults.standardUserDefaults().integerForKey(LastSelectedSessionTabIndex)
			segmentControl?.selectedSegment = lastSelection
			sidebar.selectedTabViewItemIndex = lastSelection
			return true
		}
		return false
	}

	dynamic func tabSwitcherClicked(sender:AnyObject?) {
		let sidebar = sidebarTabController()
		let splitItem = splitViewItems[0]
		let index = (segmentControl?.selectedSegment)!
		if index == sidebar.selectedTabViewItemIndex {
			//same as currently selected. toggle visibility
			segmentControl?.animator().setSelected(splitItem.collapsed, forSegment: index)
			toggleSidebar(nil)
		} else {
			if splitItem.collapsed {
				toggleSidebar(self)
			}
			segmentControl?.animator().setSelected(true, forSegment: index)
			sidebar.selectedTabViewItemIndex = index
			NSUserDefaults.standardUserDefaults().setInteger(index, forKey: LastSelectedSessionTabIndex)
		}
	}

	func sidebarTabController() -> NSTabViewController {
		return self.childViewControllers[0] as! NSTabViewController
	}
}
