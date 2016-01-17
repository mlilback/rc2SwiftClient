//
//  SystemExtensions.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

enum ColorInputError : ErrorType {
	case InvalidHexString
}

#if os(OSX)
	import AppKit
	typealias Color = NSColor
	typealias Image = NSImage
#else
	import UIKit
	typealias Color = UIColor
	typealias Image = UIImage
#endif

extension Color {
	public convenience init(hex:String, alpha:CGFloat = 1.0) throws {
		var hcode = hex
		if hcode.hasPrefix("#") {
			hcode = hcode.substringFromIndex(hcode.characters.startIndex.advancedBy(1))
		}
		var hexValue: UInt32 = 0
		guard NSScanner(string:hcode).scanHexInt(&hexValue) else {
			throw ColorInputError.InvalidHexString
		}
		let divisor = CGFloat(255)
		let red = CGFloat((hexValue & 0xFF0000) >> 24) / divisor
		let blue = CGFloat((hexValue & 0x00FF00) >> 16) / divisor
		let green = CGFloat((hexValue & 0x0000FF) >> 8) / divisor
		self.init(red:red, green:green, blue:blue, alpha:alpha)
	}
}

extension NSRange {
	func toStringRange(str:String) -> Range<String.Index>? {
		let fromIdx = str.utf16.startIndex.advancedBy(self.location)
		let toIdx = fromIdx.advancedBy(self.length, limit: str.utf16.endIndex)
		if let from = String.Index(fromIdx, within: str),
			let to = String.Index(toIdx, within: str)
		{
			return from ..< to
		}
		return nil
	}
}

