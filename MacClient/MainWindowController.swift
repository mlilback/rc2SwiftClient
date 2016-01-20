//
//  MainWindowController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

class MainWindowController: NSWindowController, ToolbarDelegatingOwner {
	override func windowDidLoad() {
		assignHandlers(contentViewController!, items: (window?.toolbar?.items)!)
	}
}
