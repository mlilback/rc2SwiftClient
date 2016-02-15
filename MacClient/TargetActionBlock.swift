//
//  TargetActionBlock.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

class TargetActionBlock: NSObject {
	typealias ActionBlock = ((AnyObject) -> Void)
	let actionBlock:ActionBlock
	private struct Keys {
		static var SelfName = "rc2_SelfName"
	}
	
	init(action:ActionBlock) {
		self.actionBlock = action
		super.init()
	}
	
	func performAction(sender:AnyObject?) {
		actionBlock(sender == nil ? self : sender!)
	}
	
	func installInToolbarItem(item:NSToolbarItem) {
		item.target = self
		item.action = "performAction:"
		objc_setAssociatedObject(item, &Keys.SelfName, self, .OBJC_ASSOCIATION_RETAIN)
	}
	
	func installInControl(item:NSControl) {
		item.target = self
		item.action = "performAction:"
		objc_setAssociatedObject(item, &Keys.SelfName, self, .OBJC_ASSOCIATION_RETAIN)
	}
}
