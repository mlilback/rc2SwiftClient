//
//  ToolbarItemHandler.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

protocol ToolbarItemHandler : class {
	///called by a top level controller for each toolbar item no one has claimed
	func handlesToolbarItem(item: NSToolbarItem) -> Bool
	///shoudl be called in viewDidAppear for lazy loaded views to hookup to toolbar items
	func hookupToToolbarItems(handler:ToolbarItemHandler, window:NSWindow)
}

protocol ToolbarDelegatingOwner : class {
	//should be called when views have loaded
	func assignHandlers(rootController: NSViewController, items:[NSToolbarItem])
	///called by hookupToolbarItems so a lazy-loaded controller can hook up items it supports
	func assignUnclaimedToolbarItems(toolbar:NSToolbar, handler:ToolbarItemHandler)
}

extension ToolbarItemHandler {
	func hookupToToolbarItems(handler:ToolbarItemHandler, window:NSWindow) {
		//find owner
		if let owner:ToolbarDelegatingOwner = firstChildViewController(window.contentViewController!) {
			owner.assignUnclaimedToolbarItems(window.toolbar!, handler: handler)
		}
	}
}

extension ToolbarDelegatingOwner {
	func assignUnclaimedToolbarItems(toolbar:NSToolbar, handler:ToolbarItemHandler) {
		for item in toolbar.items {
			if item.action == nil {
				handler.handlesToolbarItem(item)
			}
		}
	}
	
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
