//
//  AppKitExtensions.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

extension NSFontDescriptor {
	var fontName: String { return object(forKey: NSFontDescriptor.AttributeName.name) as? String ?? "Unknown" }
	var visibleName: String { return object(forKey: NSFontDescriptor.AttributeName.visibleName) as? String ?? fontName }
}

extension NSFont {
	/// Returns a font with the size adjusted to fit string in maxWidth pixels, limited to minFontSize. The font will never be larger than minFontSize
	///
	/// - Parameters:
	///   - string: the string to base the font size on
	///   - maxWidth: the maximum width of the display rect for string
	///   - minFontSize: the minimum font size, defaults to 9.0.
	/// - Returns: an adjusted font
	func font(for string: String, maxWidth: CGFloat, minFontSize: CGFloat = 9.0) -> NSFont {
		let increment: CGFloat = 0.2
		var curSize: CGFloat = 14.0
		var sz = string.size(withAttributes: [NSAttributedStringKey.font: self])
		if sz.width < maxWidth { return self }
		var curFont = self
		while sz.width > maxWidth && (curSize - increment) > minFontSize {
			curSize -= increment
			curFont = NSFont(name: fontName, size: curSize)!
			sz = string.size(withAttributes: [NSAttributedStringKey.font: curFont])
		}
		return curFont
	}
}

extension NSMenu {
	func itemWithAction(_ action: Selector, recursive: Bool = true) -> NSMenuItem? {
		for anItem in items where anItem.action == action {
			return anItem
		}
		if recursive {
			for anItem in items {
				if let theItem = anItem.submenu?.itemWithAction(action, recursive: true) {
					return theItem
				}
			}
		}
		return nil
	}
}
