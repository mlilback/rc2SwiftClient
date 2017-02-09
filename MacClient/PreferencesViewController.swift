//
//  PreferencesViewController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

class PreferencesViewController: NSTabViewController {
	lazy var tabSizes = [String: NSSize]()
	
	override func tabView(_ tabView: NSTabView, willSelect tabViewItem: NSTabViewItem?)
	{
		_ = tabView.selectedTabViewItem
		super.tabView(tabView, willSelect: tabViewItem)
		let origSize = tabSizes[tabViewItem!.label]
		if origSize == nil {
			tabSizes[tabViewItem!.label] = tabViewItem!.view!.frame.size
		}
	}
	
	override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?)
	{
		defer { super.tabView(tabView, didSelect: tabViewItem) }
		guard let window = self.view.window else { return }
		window.title = tabViewItem!.label
		let size = tabSizes[tabViewItem!.label]!
		let contentFrame = window.frameRect(forContentRect: NSMakeRect(0, 0, size.width, size.height))
		var frame = window.frame
		frame.origin.y = frame.origin.y + (frame.size.height - contentFrame.size.height)
		frame.size.height = contentFrame.size.height
		frame.size.width = contentFrame.size.width
		window.setFrame(frame, display: true, animate: true)
	}
}
