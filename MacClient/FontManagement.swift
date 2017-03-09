//
//  FontManagement.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

extension Selector {
	static let showFonts = #selector(ManageFontMenu.showFonts(_:))
	static let showFontSizes = #selector(ManageFontMenu.showFontSizes(_:))
	static let adjustFontSize = #selector(ManageFontMenu.adjustFontSize(_:))
}

@objc protocol UsesAdjustableFont {
	func fontsEnabled() -> Bool
	///The menu item will have a font descriptor as the representedObject
	func fontChanged(_ menuItem:NSMenuItem)
	var currentFontDescriptor:NSFontDescriptor { get set }
}

@objc protocol ManageFontMenu {
	///function that if implemented will cause validatemenuItem to be called with the Font menu item
	func showFonts(_ sender: AnyObject?)
	///function that if implemented will cause validatemenuItem to be called with the Font size menu item
	func showFontSizes(_ sender: AnyObject?)
	///should be action for each size font menu item
	/// - parameter sender: the menu item. The size is the tag value, if zero, user should be asked for a custom value
	func adjustFontSize(_ sender: NSMenuItem)
}

func currentFontUser(_ firstResponder:NSResponder?) -> UsesAdjustableFont? {
	var curResponder = firstResponder
	while (curResponder != nil) {
		if let fontHandler = curResponder as? UsesAdjustableFont {
			return fontHandler
		}
		curResponder = curResponder?.nextResponder
	}
	return nil
}
