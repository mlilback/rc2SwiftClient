//
//  String+Rc2Extensions.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

public extension String {
	///convience property equal to the range of entire string
	public var fullRange: Range<Index> { return startIndex..<endIndex }
	///convience property equal to the NSRange of the entire string
	public var toNSRange: NSRange { return NSRange(location: 0, length: characters.count) }

	fileprivate struct CharSetStatics {
		static var urlAllowedCharacters: CharacterSet = {
			let unreserved = "-._~/?"
			let allowed = NSMutableCharacterSet.alphanumeric()
			allowed.addCharacters(in: unreserved)
			return allowed as CharacterSet
		}()

		static var formAllowedCharacters: CharacterSet = {
			let unreserved = "*-._"
			let allowed = NSMutableCharacterSet.alphanumeric()
			allowed.addCharacters(in: unreserved)
			allowed.addCharacters(in: " ")
			return allowed as CharacterSet
		}()
	}

	///from http://useyourloaf.com/blog/how-to-percent-encode-a-url-string/
	public func stringByAddingPercentEncodingForURL() -> String? {
		return addingPercentEncoding(withAllowedCharacters: CharSetStatics.urlAllowedCharacters)
	}

	///from http://useyourloaf.com/blog/how-to-percent-encode-a-url-string/
	/// converts spaces to +
	public func stringByAddingPercentEncodingForFormData() -> String? {
		let unreserved = "*-._"
		let allowed = NSMutableCharacterSet.alphanumeric()
		allowed.addCharacters(in: unreserved)
		allowed.addCharacters(in: " ")

		var encoded = addingPercentEncoding(withAllowedCharacters: CharSetStatics.formAllowedCharacters)
		encoded = encoded?.replacingOccurrences(of: " ", with: "+")
		return encoded
	}
}
