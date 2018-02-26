//
//  SidebarTabController.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

class SidebarTabController: NSTabViewController {
	let LastSelectionKey = "LastSelectionKey"
	
	var selectedTabIndex: Int {
		return tabView.indexOfTabViewItem((tabView.selectedTabViewItem)!)
	}
}
