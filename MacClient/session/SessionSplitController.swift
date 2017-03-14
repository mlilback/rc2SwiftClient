//
//  SessionSplitController
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

let LastSelectedSessionTabIndex = "LastSelectedSessionTabIndex"
let SidebarFixedWidth: CGFloat = 209

enum SidebarTab: Int {
	case files = 0, variables, helpTopics
}

class SessionSplitController: NSSplitViewController, ToolbarItemHandler {
	var sidebarSegmentControl: NSSegmentedControl?
	var outputSegmentControl: NSSegmentedControl?

	override func awakeFromNib() {
		super.awakeFromNib()
		let splitItem = sidebarSplitItem()
		splitItem.minimumThickness = SidebarFixedWidth
		splitItem.maximumThickness = SidebarFixedWidth
		splitItem.isSpringLoaded = false
	}
	
	func handlesToolbarItem(_ item: NSToolbarItem) -> Bool {
		if item.itemIdentifier == "leftView" {
			sidebarSegmentControl = item.view as! NSSegmentedControl? // swiftlint:disable:this force_cast
			sidebarSegmentControl?.target = self
			sidebarSegmentControl?.action = #selector(SessionSplitController.sidebarSwitcherClicked(_:))
			let sidebar = sidebarTabController()
			let lastSelection = UserDefaults.standard.integer(forKey: LastSelectedSessionTabIndex)
			sidebarSegmentControl?.selectedSegment = lastSelection
			sidebar.selectedTabViewItemIndex = lastSelection
			return true
		} else if item.itemIdentifier == "rightView" {
			outputSegmentControl = item.view as! NSSegmentedControl? // swiftlint:disable:this force_cast
			outputSegmentControl?.target = self
			outputSegmentControl?.action = #selector(SessionSplitController.outputSwitcherClicked(_:))
			outputSegmentControl?.selectedSegment = 0
			outputTabController().selectedOutputTab.value = .console
			return true
		}
		return false
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		outputTabController().selectedOutputTab.signal.observeValues { value in
			self.outputSegmentControl?.selectSegment(withTag: value.rawValue)
		}
	}
	
	override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		guard let action = menuItem.action else { return super.validateMenuItem(menuItem) }
		switch action {
		case Selector.switchSidebarTab:
			if sidebarSplitItem().isCollapsed {
				menuItem.state = NSOffState
			} else {
				menuItem.state = menuItem.tag == sidebarSegmentControl?.selectedSegment ? NSOnState : NSOffState
			}
			return true
		case Selector.switchOutputTab:
			menuItem.state = menuItem.tag == outputSegmentControl?.selectedSegment ? NSOnState : NSOffState
			return true
		default:
			return super.validateMenuItem(menuItem)
		}
	}
	
	func outputSwitcherClicked(_ sender: NSSegmentedControl) {
		guard let tab = OutputTab(rawValue: sender.selectedSegment) else { fatalError() }
		outputTabController().selectedOutputTab.value = tab
	}

	@IBAction func switchOutputTab(_ sender: NSMenuItem?) {
		guard let tab = OutputTab(rawValue: sender?.tag ?? -1) else { fatalError() }
		outputTabController().selectedOutputTab.value = tab
		outputSegmentControl?.selectSegment(withTag: tab.rawValue)
	}
	
	//action for sidebar segmented control
	func sidebarSwitcherClicked(_ sender: NSSegmentedControl) {
		guard let tab = SidebarTab(rawValue: sender.selectedSegment) else { fatalError() }
		switchSidebarTo(tab: tab)
	}
	
	//action for menu items
	@IBAction func switchSidebarTab(_ sender: NSMenuItem?) {
		guard let tab = SidebarTab(rawValue: sender?.tag ?? -1) else { fatalError() }
		switchSidebarTo(tab: tab)
	}
	
	func switchSidebarTo(tab: SidebarTab) {
		let index = tab.rawValue
		let sidebar = sidebarTabController()
		let splitItem = sidebarSplitItem()
//		let index = (segmentControl?.selectedSegment)!
		if index == sidebar.selectedTabViewItemIndex {
			//same as currently selected. toggle visibility
			sidebarSegmentControl?.animator().setSelected(splitItem.isCollapsed, forSegment: index)
			
//			toggleSidebar(nil)
			splitItem.isCollapsed = !splitItem.isCollapsed
		} else {
			if splitItem.isCollapsed {
				splitItem.isCollapsed = false
//				toggleSidebar(self)
			}
			sidebarSegmentControl?.animator().setSelected(true, forSegment: index)
			sidebar.selectedTabViewItemIndex = index
			UserDefaults.standard.set(index, forKey: LastSelectedSessionTabIndex)
		}
	}

	func sidebarSplitItem() -> NSSplitViewItem {
		return self.splitViewItems.first(where: { $0.viewController == sidebarTabController() })!
	}
	
	func sidebarTabController() -> NSTabViewController {
		// swiftlint:disable:next force_cast
		return self.childViewControllers.first(where: { $0.identifier == "sidebarTabController" }) as! NSTabViewController
	}
	
	func outputTabController() -> OutputTabController {
		// swiftlint:disable:next force_cast
		return self.childViewControllers.first(where: { $0.identifier == "outputTabController" }) as! OutputTabController
	}
	
	override func splitView(_ splitView: NSSplitView, shouldHideDividerAt dividerIndex: Int) -> Bool {
		return false
	}
}
