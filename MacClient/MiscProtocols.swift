//
//  MiscProtocols.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

@objc protocol UsesAdjustableFont {
	func fontsEnabled() -> Bool
	///The menu will have a font descriptor as the representedObject
	func fontChanged(menuItem:NSMenuItem)
	var currentFontDescriptor:NSFontDescriptor { get }
}

@objc protocol ManageFontMenu {
	///function that if implemented will cause validatemenuItem to be called with the Font menu item
	func showFonts(sender:AnyObject)
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
