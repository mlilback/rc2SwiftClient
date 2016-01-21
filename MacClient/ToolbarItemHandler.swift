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
		//find every ToolbarItemHandler in rootController
		let handlers = recursiveFlatMap(rootController, transform: { $0 as? ToolbarItemHandler }, children: { $0.childViewControllers })
		//loop through toolbar items looking for the first handler that handles the item
		for anItem in items {
			for aHandler in handlers {
				if aHandler.handlesToolbarItem(anItem) { break; }
			}
		}
	}
}
