//
//  ToolbarItemHandler.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

protocol ToolbarItemHandler : class {
	///called by a top level controller for each toolbar item no one has claimed
	func handlesToolbarItem(item: NSToolbarItem) -> Bool
}

protocol ToolbarDelegatingOwner : class {
	func assignHandlers(rootController: NSViewController, items:[NSToolbarItem])
}

extension ToolbarDelegatingOwner {
	func assignHandlers(rootController: NSViewController, items:[NSToolbarItem]) {
		//find every ToolbarItemHandler in window
		var handlers: [ToolbarItemHandler] = [ToolbarItemHandler]()
		handlersForController(rootController, matches: &handlers)
		//loop through toolbar items looking for the first handler that handles the item
		for anItem in items {
			for aHandler in handlers {
				if aHandler.handlesToolbarItem(anItem) { break; }
			}
		}
	}
	
	private func handlersForController(parent: NSViewController, inout matches: [ToolbarItemHandler]) {
		for aController in parent.childViewControllers {
			if aController is ToolbarItemHandler {
				matches.append(aController as! ToolbarItemHandler)
			}
			handlersForController(aController, matches: &matches)
		}
	}
}
