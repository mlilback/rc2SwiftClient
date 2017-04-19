//
//  NSRange+Docker.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

public extension NSRange {
	public func toStringRange(_ str: String) -> Range<String.Index>? {
		guard str.characters.count >= length - location && location < str.characters.count else { return nil }
		let fromIdx = str.characters.index(str.startIndex, offsetBy: self.location)
		guard let toIdx = str.characters.index(fromIdx, offsetBy: self.length, limitedBy: str.endIndex) else { return nil }
		return fromIdx..<toIdx
	}
}

public func MaxNSRangeIndex(_ range: NSRange) -> Int {
	return range.location + range.length - 1
}
