//
//  String+Rc2Extensions.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

extension String {
	///convience property equal to the range of entire string
	public var fullRange:Range<Index> { return self.startIndex..<self.endIndex }
	///convience property equal to the NSRange of the entire string
	public var toNSRange:NSRange { return NSMakeRange(0, characters.count) }
}
