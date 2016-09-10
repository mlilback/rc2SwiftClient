//
//  String+Rc2Extensions.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

public extension String {
	///convience property equal to the range of entire string
	public var fullRange:Range<Index> { return self.startIndex..<self.endIndex }
	///convience property equal to the NSRange of the entire string
	public var toNSRange:NSRange { return NSMakeRange(0, characters.count) }

	private struct CharSetStatics {
		static var urlAllowedCharacters:NSCharacterSet = {
			let unreserved = "-._~/?"
			let allowed = NSMutableCharacterSet.alphanumericCharacterSet()
			allowed.addCharactersInString(unreserved)
			return allowed
		}()

		static var formAllowedCharacters:NSCharacterSet = {
			let unreserved = "*-._"
			let allowed = NSMutableCharacterSet.alphanumericCharacterSet()
			allowed.addCharactersInString(unreserved)
			allowed.addCharactersInString(" ")
			return allowed
		}()
	}
	
	///from http://useyourloaf.com/blog/how-to-percent-encode-a-url-string/
	public func stringByAddingPercentEncodingForURL() -> String? {
		return stringByAddingPercentEncodingWithAllowedCharacters(CharSetStatics.urlAllowedCharacters)
	}

	///from http://useyourloaf.com/blog/how-to-percent-encode-a-url-string/
	/// converts spaces to +
	public func stringByAddingPercentEncodingForFormData() -> String? {
		let unreserved = "*-._"
		let allowed = NSMutableCharacterSet.alphanumericCharacterSet()
		allowed.addCharactersInString(unreserved)
		allowed.addCharactersInString(" ")
		
		var encoded = stringByAddingPercentEncodingWithAllowedCharacters(CharSetStatics.formAllowedCharacters)
		encoded = encoded?.stringByReplacingOccurrencesOfString(" ", withString: "+")
		return encoded
	}
}
