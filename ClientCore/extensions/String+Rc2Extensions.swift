//
//  String+Rc2Extensions.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

public extension String {
	/// Returns the range that encompases the entire string
	public var fullRange: Range<Index> { return startIndex..<endIndex }
	/// Returns the NSRange that encompases the entire string
	public var fullNSRange: NSRange { return NSRange(location: 0, length: utf16.count) }

	/// Converts an NSRange to a Range<String.Index>
	///
	/// - parameter nsRange: the NSRange to convert
	///
	/// - returns: the matching string range
	func range(from nsRange: NSRange) -> Range<String.Index>? {
		guard
			let from16 = utf16.index(utf16.startIndex, offsetBy: nsRange.location, limitedBy: utf16.endIndex),
			let to16 = utf16.index(from16, offsetBy: nsRange.length, limitedBy: utf16.endIndex),
			let from = String.Index(from16, within: self),
			let to = String.Index(to16, within: self)
			else { return nil }
		return from ..< to
	}

	/// retrieve the substring represented by an NSRange
	///
	/// - parameter from: the desired range
	///
	/// - returns: the substring, or nil if the range is invalid
	func substring(from: NSRange) -> String? {
		guard let range = range(from: from) else { return nil }
		return substring(with: range)
	}
}
