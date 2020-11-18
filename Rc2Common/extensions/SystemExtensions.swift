//
//  SystemExtensions.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

//FIXME: code smell
public func delay(_ delay: Double, _ closure:@escaping () -> Void) {
	DispatchQueue.main.asyncAfter(
		deadline: DispatchTime.now() + Double(Int64(delay * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC), execute: closure)
}

public extension NotificationCenter {
	/// Posts a notification on the deffault center on the main thread with the specified paramters
	/// - Parameters:
	///   - name: the name of the notification to post
	///   - object: the object related to the notification
	///   - userInfo: Dictionary of parameters
	func postNotificationNameOnMainThread(_ name: NSNotification.Name, object: AnyObject, userInfo: [AnyHashable: Any]? = nil) {
		if !Thread.isMainThread {
			postAsyncNotificationNameOnMainThread(name, object: object, userInfo: userInfo)
		} else {
			post(name: name, object: object, userInfo: userInfo)
		}
	}
	/// Posts a notification on the deffault center aysnchronously on the main thread with the specified paramters
	/// - Parameters:
	///   - name: the name of the notification to post
	///   - object: the object related to the notification
	///   - userInfo: Dictionary of parameters
	func postAsyncNotificationNameOnMainThread(_ name: Notification.Name, object: AnyObject, userInfo: [AnyHashable: Any]?=nil) {
		DispatchQueue.main.async(execute: {
			self.post(name: name, object: object, userInfo: userInfo)
		})
	}
}

public extension NSRange {
	/// Converts to a Swift String range
	/// - Parameter str: the string this range applies to
	/// - Returns: a swift range that matdches self in passed in string
	func toStringRange(_ str: String) -> Range<String.Index>? {
		guard str.count >= length - location && location < str.count else { return nil }
		let fromIdx = str.index(str.startIndex, offsetBy: self.location)
		guard let toIdx = str.index(fromIdx, offsetBy: self.length, limitedBy: str.endIndex) else { return nil }
		return fromIdx..<toIdx
	}
}

//swiftlint:disable:next identifier_name
public func MaxNSRangeIndex(_ range: NSRange) -> Int {
	return range.location + range.length - 1
}
