//
//  XAttributeManager.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Darwin

/// options for AttributeManager calls
public struct XAttributeOptions: OptionSet {
	public let rawValue: Int32
	
	public init(rawValue: Int32) {
		self.rawValue = rawValue
	}
	
	/// XATTR_NOFOLLOW
	static public let noFollow = XAttributeOptions(rawValue: XATTR_NOFOLLOW)
	/// XATTR_CREATE
	static public let failIfExists = XAttributeOptions(rawValue: XATTR_CREATE)
	/// XATTR_REPLACE
	static public let failIfNotExists = XAttributeOptions(rawValue: XATTR_REPLACE)
}

/// wrapper around darwin calls setxattr, getxattr, removexattr
public protocol AttributeManager {
	/// Lists extended attributes for a file (syntactic sugar for listxattr)
	///
	/// - Parameters:
	///   - url: the file to query for attribute names
	///   - options: options passed to listxattr
	/// - Returns: array of attribute names
	/// - Throws: NSError with a POSIXErrorCode
	func listAttributes(at url: URL, options: XAttributeOptions) throws -> [String]

	/// Sets the extended attribute of a file (syntactic sugar for setxattr)
	///
	/// - Parameters:
	///   - named: the name of the attribute
	///   - data: the data to store as the value of the attribute
	///   - forURL: the URL of the file to set the attribute on
	///   - options: options to pass to setxattr
	/// - Throws: an NSError with a POSIXErrorCode
	func setAttribute(named: String, data: Data, forURL: URL, options: XAttributeOptions) throws
	
	
	/// Gets the value of an extended attribute (syntactic sugar for getxattr)
	///
	/// - Parameters:
	///   - named: name of the attribute
	///   - forURL: URL of the file
	///   - options: options to pass to getxattr
	/// - Returns: data stored in the extended attribute or nil if no such attribute exists
	/// - Throws: NSError with a POSIXErrorCode
	func getAttributeData(named: String, forURL: URL, options: XAttributeOptions) throws -> Data?
	
	
	/// Removes an extended attribute (syntactic sugar for removexattr)
	///
	/// - Parameters:
	///   - named: name of the attribute
	///   - forURL: URL of the file
	///   - options: options to pass to removexattr
	/// - Throws: NSError with a POSIXErrorCode
	func removeAttribute(named: String, forURL: URL, options: XAttributeOptions) throws
}

public class XAttributeManager: AttributeManager {
	public func listAttributes(at url: URL, options: XAttributeOptions) throws -> [String] {
		precondition(url.isFileURL)
		let bufLength = listxattr(url.path, nil, 0, 0)
		if bufLength == -1 {
			throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)
		}
		let buf = UnsafeMutablePointer<Int8>.allocate(capacity: bufLength)
		defer {
			buf.deallocate()
		}
		let result = listxattr(url.path, buf, bufLength, options.rawValue)
		if result == -1 {
			throw NSError(domain: NSPOSIXErrorDomain, code: Int(result), userInfo: nil)
		}
		guard var names = NSString(bytes: buf, length: bufLength, encoding: String.Encoding.utf8.rawValue)?.components(separatedBy: "\0") else {
			return []
		}
		names.removeLast()
		return names
	}
	
	public func setAttribute(named name: String, data: Data, forURL url: URL, options: XAttributeOptions = []) throws {
		precondition(url.isFileURL)
		let result: Int32 = data.withUnsafeBytes { buffer in
			return setxattr(url.path, name, buffer, data.count, 0, options.rawValue)
		}
		guard result == 0 else {
			throw NSError(domain: NSPOSIXErrorDomain, code: Int(result), userInfo: nil)
		}
	}
	
	public func getAttributeData(named name: String, forURL url: URL, options: XAttributeOptions) throws -> Data? {
		precondition(url.isFileURL)
		let bufLength = getxattr(url.path, name, nil, 0, 0, options.rawValue)
		if bufLength == -1 {
			throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)
		}
		let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufLength, alignment: MemoryLayout<UInt8>.alignment)
		defer {
			buffer.deallocate()
		}
		let result = getxattr(url.path, name, buffer, bufLength, 0, options.rawValue)
		if result == -1 {
			throw NSError(domain: NSPOSIXErrorDomain, code: Int(result), userInfo: nil)
		}
		return Data(bytes: buffer, count: bufLength)
	}
	
	public func removeAttribute(named name: String, forURL url: URL, options: XAttributeOptions) throws {
		precondition(url.isFileURL)
		let result: Int32 = removexattr(url.path, name, options.rawValue)
		guard result == 0 else {
			throw NSError(domain: NSPOSIXErrorDomain, code: Int(result), userInfo: nil)
		}
	}
}
