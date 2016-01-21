//
//  MainWindowController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

class MainWindowController: NSWindowController, ToolbarDelegatingOwner, NSToolbarDelegate {
	@IBOutlet var rootTabController: NSTabViewController?
	private var toolbarSetupScheduled = false
	
	func toolbarWillAddItem(notification: NSNotification) {
		//schedule assigning handlers after toolbar items are loaded
		if !toolbarSetupScheduled {
			dispatch_async(dispatch_get_main_queue()) { () -> Void in
				self.assignHandlers(self.contentViewController!, items: (self.window?.toolbar?.items)!)
			}
			toolbarSetupScheduled = true
		}
	}
}
