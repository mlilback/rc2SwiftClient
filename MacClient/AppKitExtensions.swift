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

