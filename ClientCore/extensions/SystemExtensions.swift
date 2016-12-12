//
//  SystemExtensions.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import CryptoSwift

public func delay(_ delay: Double, _ closure:@escaping ()->()) {
	DispatchQueue.main.asyncAfter(
		deadline: DispatchTime.now() + Double(Int64(delay * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC), execute: closure)
}

public enum ColorInputError: Error {
	case invalidHexString
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

// TODO: remove Box and ObjCBox
public final class Box<T> {
	public let unbox: T
	public init(_ value: T) {
		self.unbox = value
	}
}

public final class ObjcBox<T>: NSObject {
	public let unbox: T
	public init(_ value: T) {
		self.unbox = value
	}
}

public extension PlatformColor {
	// TODO: 'swiftize' method names, e.g. below as color(HexString hex: String...
	public static func colorWithHexString(_ hex: String, alpha: CGFloat = 1.0) -> PlatformColor? {
		do {
			return try PlatformColor(hex:hex, alpha:alpha)
		} catch _ {
			return nil
		}
	}
	public convenience init(hex: String, alpha: CGFloat = 1.0) throws {
		var hcode = hex
		if hcode.hasPrefix("#") {
			hcode = hcode.substring(from: hcode.characters.index(hcode.characters.startIndex, offsetBy: 1))
		}
		let redHex = hex.substring(to: hex.characters.index(hex.startIndex, offsetBy: 2))
		let greenHex = hex.substring(with: hex.characters.index(hex.startIndex, offsetBy: 2) ..< hex.characters.index(hex.startIndex, offsetBy: 4))
		let blueHex = hex.substring(with: hex.characters.index(hex.startIndex, offsetBy: 4) ..< hex.characters.index(hex.startIndex, offsetBy: 6))
		var redInt: CUnsignedInt = 0
		var greenInt: CUnsignedInt = 0
		var blueInt: CUnsignedInt = 0
		Scanner(string: redHex).scanHexInt32(&redInt)
		Scanner(string: greenHex).scanHexInt32(&greenInt)
		Scanner(string: blueHex).scanHexInt32(&blueInt)
		let divisor: CGFloat = 255.0

		self.init(red:CGFloat(redInt) / divisor, green:CGFloat(greenInt) / divisor, blue:CGFloat(blueInt) / divisor, alpha:alpha)
	}
}

// TODO: possibily get rid of NotificationCenter
public extension NotificationCenter {
	func postNotificationNameOnMainThread(_ name: NSNotification.Name, object: AnyObject, userInfo: [AnyHashable: Any]?=nil) {
		if !Thread.isMainThread {
			postAsyncNotificationNameOnMainThread(name, object: object, userInfo:userInfo)
		} else {
			post(name: name, object: object, userInfo: userInfo)
		}
	}
	func postAsyncNotificationNameOnMainThread(_ name: Notification.Name, object: AnyObject, userInfo: [AnyHashable: Any]?=nil) {
		DispatchQueue.main.async(execute: {
			self.post(name: name, object: object, userInfo: userInfo)
		})
	}
}

public extension NSRange {
	public func toStringRange(_ str: String) -> Range<String.Index>? {
		guard str.characters.count >= length - location  && location < str.characters.count else { return nil }
		let fromIdx = str.characters.index(str.startIndex, offsetBy: self.location)
		guard let toIdx = str.characters.index(fromIdx, offsetBy: self.length, limitedBy: str.endIndex) else { return nil }
		return fromIdx..<toIdx
	}
}

public func MaxNSRangeIndex(_ range: NSRange) -> Int {
	return range.location + range.length - 1
}
