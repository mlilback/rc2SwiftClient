//
//  TargetActionBlock.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

///wrapper around a block for use as a target/action combo.
class TargetActionBlock: NSObject {
	typealias ActionBlock = ((Any) -> Void)
	let actionBlock: ActionBlock
	fileprivate struct Keys {
		static var SelfName = "rc2_SelfName"
	}
	
	/// Create an instance for a specified block
	///
	/// - Parameter action: the block to execute when this target/action is called
	init(action: @escaping ActionBlock) {
		self.actionBlock = action
		super.init()
	}
	
	/// called to execute the block as an action
	@objc func performAction(_ sender: Any?) {
		actionBlock(sender == nil ? self : sender!)
	}
	
	/// Install this target/action into a toolbar item. The item will keep a strong reference to this object.
	///
	/// - Parameter item: toolbar item whose target/action should be set to call this object
	func installInToolbarItem(_ item: NSToolbarItem) {
		item.target = self
		item.action = #selector(TargetActionBlock.performAction(_:))
		objc_setAssociatedObject(item, &Keys.SelfName, self, .OBJC_ASSOCIATION_RETAIN)
	}
	
	/// Install this target/action into a control. The control will keep a strong reference to this object.
	///
	/// - Parameter item: control whose target/action should be set to call this object
	func installInControl(_ item: NSControl) {
		item.target = self
		item.action = #selector(TargetActionBlock.performAction(_:))
		objc_setAssociatedObject(item, &Keys.SelfName, self, .OBJC_ASSOCIATION_RETAIN)
	}
}
