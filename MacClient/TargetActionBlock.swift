//
//  TargetActionBlock.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

class TargetActionBlock: NSObject {
	typealias ActionBlock = ((AnyObject) -> Void)
	let actionBlock:ActionBlock
	fileprivate struct Keys {
		static var SelfName = "rc2_SelfName"
	}
	
	init(action:@escaping ActionBlock) {
		self.actionBlock = action
		super.init()
	}
	
	func performAction(_ sender:AnyObject?) {
		actionBlock(sender == nil ? self : sender!)
	}
	
	func installInToolbarItem(_ item:NSToolbarItem) {
		item.target = self
		item.action = #selector(TargetActionBlock.performAction(_:))
		objc_setAssociatedObject(item, &Keys.SelfName, self, .OBJC_ASSOCIATION_RETAIN)
	}
	
	func installInControl(_ item:NSControl) {
		item.target = self
		item.action = #selector(TargetActionBlock.performAction(_:))
		objc_setAssociatedObject(item, &Keys.SelfName, self, .OBJC_ASSOCIATION_RETAIN)
	}
}
