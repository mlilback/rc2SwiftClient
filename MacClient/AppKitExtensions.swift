//
//  AppKitExtensions.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

extension NSFontDescriptor {
	var fontName:String { return objectForKey(NSFontNameAttribute) as? String ?? "Unknown" }
	var visibleName:String { return objectForKey(NSFontVisibleNameAttribute) as? String ?? fontName }
}

extension NSMenu {
	func itemWithAction(action:Selector, recursive:Bool = true) -> NSMenuItem? {
		for anItem in itemArray {
			if anItem.action == action {
				return anItem
			}
		}
		if recursive {
			for anItem in itemArray {
				if let theItem = anItem.submenu?.itemWithAction(action, recursive: true) {
					return theItem
				}
			}
		}
		return nil
	}
}