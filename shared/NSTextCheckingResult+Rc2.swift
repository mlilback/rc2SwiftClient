//
//  NSTextCheckingResult+Rc2.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

extension NSTextCheckingResult {
	///returns the substring of inputString at the specified range
	func stringAtIndex(index:Int, forString inputString:String) -> String? {
		guard let strRange = rangeAtIndex(index).toStringRange(inputString) else { return nil }
		return inputString.substringWithRange(strRange)
	}
}
