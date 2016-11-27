//
//  NSError+Rc2.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

// TODO: remove
public extension NSError {
	///returns a NSError with the domain of Rc2ErrorDomain
	/// - parameter withCode: the Rc2 error code for this error
	/// - parameter description: if nil, will be looked up with NSLocalizedString using Rc2ErrorCode.[code]
	/// - returns: the new error object
	static func error(withCode code: Rc2ErrorCode, description: String?, underlyingError: NSError? = nil) -> NSError {
		var userInfo: [String:AnyObject]? = [:]
		var localDescription = description
		if localDescription == nil {
			localDescription = NSLocalizedString("Rc2ErrorCode.\(code)", comment: "")
		}
		if let desc = localDescription {
			userInfo?[NSLocalizedDescriptionKey] = desc as AnyObject?
		}
		if underlyingError != nil { userInfo?[NSUnderlyingErrorKey] = underlyingError }
		if userInfo?.count ?? 0 < 1 { userInfo = nil }
		return NSError(domain: Rc2ErrorDomain, code: code.rawValue, userInfo: userInfo)
	}
}
