//
//  SidebarTabController.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

class SidebarTabController: NSTabViewController {
	let LastSelectionKey = "LastSelectionKey"
	
	var selectedTabIndex: Int {
		get { return tabView.indexOfTabViewItem((tabView.selectedTabViewItem)!) }
	}
	
	func selectTabAtIndex(index: Int) {
		tabView.selectTabViewItemAtIndex(index)
	}
}

