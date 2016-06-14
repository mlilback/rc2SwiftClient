//
//  MiscProtocols.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

@objc protocol UsesAdjustableFont {
	func fontsEnabled() -> Bool
	///The menu item will have a font descriptor as the representedObject
	func fontChanged(menuItem:NSMenuItem)
	var currentFontDescriptor:NSFontDescriptor { get set }
}

@objc protocol ManageFontMenu {
	///function that if implemented will cause validatemenuItem to be called with the Font menu item
	func showFonts(sender:AnyObject)
	///function that if implemented will cause validatemenuItem to be called with the Font size menu item
	func showFontSizes(sender:AnyObject)
	///should be action for each size font menu item
	/// - parameter sender: the menu item. The size is the tag value, if zero, user should be asked for a custom value
	func adjustFontSize(sender:NSMenuItem)
}

func currentFontUser(firstResponder:NSResponder?) -> UsesAdjustableFont? {
	var curResponder = firstResponder
	while (curResponder != nil) {
		if let fontHandler = curResponder as? UsesAdjustableFont {
			return fontHandler
		}
		curResponder = curResponder?.nextResponder
	}
	return nil
}
