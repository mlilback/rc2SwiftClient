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
		splitItem.isSpringLoaded = false
	}
	
	func handlesToolbarItem(_ item: NSToolbarItem) -> Bool {
		if item.itemIdentifier == "leftView" {
			segmentItem = item
			segmentControl = item.view as! NSSegmentedControl?
			segmentControl?.target = self
			segmentControl?.action = #selector(SessionSplitController.tabSwitcherClicked(_:))
			let sidebar = sidebarTabController()
			let lastSelection = UserDefaults.standard.integer(forKey: LastSelectedSessionTabIndex)
			segmentControl?.selectedSegment = lastSelection
			sidebar.selectedTabViewItemIndex = lastSelection
			return true
		}
		return false
	}

	func tabSwitcherClicked(_ sender:AnyObject?) {
		let sidebar = sidebarTabController()
		let splitItem = splitViewItems[0]
		let index = (segmentControl?.selectedSegment)!
		if index == sidebar.selectedTabViewItemIndex {
			//same as currently selected. toggle visibility
			segmentControl?.animator().setSelected(splitItem.isCollapsed, forSegment: index)
			
//			toggleSidebar(nil)
			splitItem.isCollapsed = !splitItem.isCollapsed
		} else {
			if splitItem.isCollapsed {
				splitItem.isCollapsed = false
//				toggleSidebar(self)
			}
			segmentControl?.animator().setSelected(true, forSegment: index)
			sidebar.selectedTabViewItemIndex = index
			UserDefaults.standard.set(index, forKey: LastSelectedSessionTabIndex)
		}
	}

	func sidebarTabController() -> NSTabViewController {
		return self.childViewControllers[0] as! NSTabViewController
	}
	
	override func splitView(_ splitView: NSSplitView, shouldHideDividerAt dividerIndex: Int) -> Bool {
		return false
	}
}
