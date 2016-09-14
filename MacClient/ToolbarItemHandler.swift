//
//  ToolbarItemHandler.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import ClientCore

protocol ToolbarItemHandler : class {
	///called by a top level controller for each toolbar item no one has claimed
	func handlesToolbarItem(_ item: NSToolbarItem) -> Bool
	///shoudl be called in viewDidAppear for lazy loaded views to hookup to toolbar items
	func hookupToToolbarItems(_ handler:ToolbarItemHandler, window:NSWindow)
}

protocol ToolbarDelegatingOwner : class {
	//should be called when views have loaded
	func assignHandlers(_ rootController: NSViewController, items:[NSToolbarItem])
	///called by hookupToolbarItems so a lazy-loaded controller can hook up items it supports
	func assignUnclaimedToolbarItems(_ toolbar:NSToolbar, handler:ToolbarItemHandler)
}

extension ToolbarItemHandler {
	func hookupToToolbarItems(_ handler:ToolbarItemHandler, window:NSWindow) {
		//find owner
		if let owner:ToolbarDelegatingOwner = firstChildViewController(window.contentViewController!) {
			owner.assignUnclaimedToolbarItems(window.toolbar!, handler: handler)
		}
	}
}

extension ToolbarDelegatingOwner {
	func assignUnclaimedToolbarItems(_ toolbar:NSToolbar, handler:ToolbarItemHandler) {
		for item in toolbar.items {
			if item.action == nil {
				_ = handler.handlesToolbarItem(item)
			}
		}
	}
	
	func assignHandlers(_ rootController: NSViewController, items:[NSToolbarItem]) {
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

//this subclass allows a closure to be injected for validation
class ValidatingToolbarItem: NSToolbarItem {
	typealias ToolbarValidationHandler = (ValidatingToolbarItem) -> Void
	var validationHandler:ToolbarValidationHandler?
	
	override func validate() {
		self.validationHandler?(self)
	}
}

