//
//  MainWindowController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

class MainWindowController: NSWindowController, ToolbarDelegatingOwner, NSToolbarDelegate {
//	override func windowDidLoad() {
//		assignHandlers(contentViewController!, items: (window?.toolbar?.items)!)
//	}
	
	func toolbarWillAddItem(notification: NSNotification) {
		dispatch_async(dispatch_get_main_queue()) { () -> Void in
			self.assignHandlers(self.contentViewController!, items: (self.window?.toolbar?.items)!)
		}
	}
}
