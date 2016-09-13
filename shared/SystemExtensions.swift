//
//  SystemExtensions.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import BrightFutures
import CryptoSwift

func delay(_ delay:Double, _ closure:@escaping ()->()) {
	DispatchQueue.main.asyncAfter(
		deadline: DispatchTime.now() + Double(Int64(delay * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC), execute: closure)
}

enum ColorInputError : Error {
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
	public static func colorWithHexString(_ hex:String, alpha:CGFloat = 1.0) -> PlatformColor? {
		do {
			return try PlatformColor(hex:hex, alpha:alpha)
		} catch _ {
			return nil
		}
	}
	public convenience init(hex:String, alpha:CGFloat = 1.0) throws {
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

extension NotificationCenter {
	func postNotificationNameOnMainThread(_ noteName:String, object:AnyObject, userInfo:[AnyHashable: Any]?=nil) {
		if !Thread.isMainThread {
			postAsyncNotificationNameOnMainThread(noteName, object: object, userInfo:userInfo)
		} else {
			post(name: Notification.Name(rawValue: noteName), object: object, userInfo: userInfo)
		}
	}
	func postAsyncNotificationNameOnMainThread(_ noteName:String, object:AnyObject, userInfo:[AnyHashable: Any]?=nil) {
		DispatchQueue.main.async(execute: {
			self.post(name: Notification.Name(rawValue: noteName), object: object, userInfo: userInfo)
		})
	}
}

extension NSError {
	public static func error(withCode code:Rc2ErrorCode, description:String?) -> NSError {
		var userInfo:[String:AnyObject]?
		if let desc = description {
			userInfo = [NSLocalizedDescriptionKey:desc as AnyObject]
		}
		return NSError(domain: Rc2ErrorDomain, code: code.rawValue, userInfo: userInfo)
	}
}

extension NSRange {
	public func toStringRange(_ str:String) -> Range<String.Index>? {
		guard str.characters.count >= length - location else { return nil }
		let fromIdx = str.characters.index(str.startIndex, offsetBy: self.location)
		let toIdx = str.characters.index(fromIdx, offsetBy: self.length)
		return fromIdx..<toIdx
	}
}

public func MaxNSRangeIndex(_ range:NSRange) -> Int {
	return range.location + range.length - 1
}

