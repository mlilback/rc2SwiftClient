//
//  SystemExtensions.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import BrightFutures
import CryptoSwift

public func delay(delay:Double, _ closure:()->()) {
	dispatch_after(
		dispatch_time(
			DISPATCH_TIME_NOW,
			Int64(delay * Double(NSEC_PER_SEC))
		),
		dispatch_get_main_queue(), closure)
}

public enum ColorInputError : ErrorType {
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
	public let unbox: T
	public init(_ value:T) {
		self.unbox = value
	}
}

public final class ObjcBox<T>: NSObject {
	public let unbox: T
	public init(_ value:T) {
		self.unbox = value
	}
}

public extension PlatformColor {
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
		let greenHex = hex.substringWithRange(hex.startIndex.advancedBy(2) ..< hex.startIndex.advancedBy(4))
		let blueHex = hex.substringWithRange(hex.startIndex.advancedBy(4) ..< hex.startIndex.advancedBy(6))
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

public extension NSNotificationCenter {
	func postNotificationNameOnMainThread(noteName:String, object:AnyObject, userInfo:[NSObject:AnyObject]?=nil) {
		if !NSThread.isMainThread() {
			postAsyncNotificationNameOnMainThread(noteName, object: object, userInfo:userInfo)
		} else {
			postNotificationName(noteName, object: object, userInfo: userInfo)
		}
	}
	func postAsyncNotificationNameOnMainThread(noteName:String, object:AnyObject, userInfo:[NSObject:AnyObject]?=nil) {
		dispatch_async(dispatch_get_main_queue(), {
			self.postNotificationName(noteName, object: object, userInfo: userInfo)
		})
	}
}

public extension NSRange {
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

public func MaxNSRangeIndex(range:NSRange) -> Int {
	return range.location + range.length - 1
}

