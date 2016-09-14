//
//  AppKitExtensions.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

extension NSFontDescriptor {
	var fontName:String { return object(forKey: NSFontNameAttribute) as? String ?? "Unknown" }
	var visibleName:String { return object(forKey: NSFontVisibleNameAttribute) as? String ?? fontName }
}

extension NSMenu {
	func itemWithAction(_ action:Selector, recursive:Bool = true) -> NSMenuItem? {
		for anItem in items {
			if anItem.action == action {
				return anItem
			}
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
