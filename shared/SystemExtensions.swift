//
//  SystemExtensions.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

func delay(delay:Double, closure:()->()) {
	dispatch_after(
		dispatch_time(
			DISPATCH_TIME_NOW,
			Int64(delay * Double(NSEC_PER_SEC))
		),
		dispatch_get_main_queue(), closure)
}

enum ColorInputError : ErrorType {
	case InvalidHexString
}

#if os(OSX)
	import AppKit
	public typealias PlatformColor = NSColor
	public typealias PlatformImage = NSImage
#else
	import UIKit
	public typealias PlatformColor = UIColor
	public typealias PlatformImage = UIImage
#endif

public final class Box<T> {
	let unbox: T
	init(_ value:T) {
		self.unbox = value
	}
}

public final class ObjcBox<T>: NSObject {
	let unbox: T
	init(_ value:T) {
		self.unbox = value
	}
}

extension PlatformColor {
	public static func colorWithHexString(hex:String, alpha:CGFloat = 1.0) -> PlatformColor? {
		do {
			return try PlatformColor(hex:hex, alpha:alpha)
		} catch _ {
			return nil
		}
	}
	public convenience init(hex:String, alpha:CGFloat = 1.0) throws {
		var hcode = hex
		if hcode.hasPrefix("#") {
			hcode = hcode.substringFromIndex(hcode.characters.startIndex.advancedBy(1))
		}
		let redHex = hex.substringToIndex(hex.startIndex.advancedBy(2))
		let greenHex = hex.substringWithRange(Range<String.Index>(start: hex.startIndex.advancedBy(2), end: hex.startIndex.advancedBy(4)))
		let blueHex = hex.substringWithRange(Range<String.Index>(start: hex.startIndex.advancedBy(4), end: hex.startIndex.advancedBy(6)))
		var redInt: CUnsignedInt = 0
		var greenInt: CUnsignedInt = 0
		var blueInt: CUnsignedInt = 0
		NSScanner(string: redHex).scanHexInt(&redInt)
		NSScanner(string: greenHex).scanHexInt(&greenInt)
		NSScanner(string: blueHex).scanHexInt(&blueInt)
		let divisor: CGFloat = 255.0
		
		self.init(red:CGFloat(redInt) / divisor, green:CGFloat(greenInt) / divisor, blue:CGFloat(blueInt) / divisor, alpha:alpha)
	}
}

extension NSFileManager {
	func copyURLToTemporaryLocation(url:NSURL) throws -> NSURL {
		let tmpDir = NSURL(fileURLWithPath:NSTemporaryDirectory()).URLByAppendingPathComponent("Rc2", isDirectory: true)
		_ = try? createDirectoryAtURL(tmpDir, withIntermediateDirectories: true, attributes: nil)
		let destUrl = NSURL(fileURLWithPath: url.lastPathComponent!, relativeToURL: tmpDir)
		_ = try? removeItemAtURL(destUrl)
		try copyItemAtURL(url, toURL: destUrl)
		return destUrl
	}
}

extension NSURL {
	func localizedName() -> String {
		var appName: String = (self.URLByDeletingPathExtension?.lastPathComponent!)!
		var appNameObj: AnyObject?
		do {
			try getResourceValue(&appNameObj, forKey: NSURLLocalizedNameKey)
			appName = appNameObj as! String
			//remove any extension
			if let dotIndex = appName.characters.indexOf(".") {
				appName = appName.substringToIndex(dotIndex)
			}
			return appName
		} catch _ {} //don't care if it failed
		return lastPathComponent!
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

