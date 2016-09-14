//
//  HTMLString.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import os

///Class that takes a string of basic html and converts it to an NSAttributedString
/// support tags are: b, i, color(hex="XXXXXX")

open class HTMLString {
	fileprivate static var basicRegex: NSRegularExpression {
		return try! NSRegularExpression(pattern: "(?:<)(b|color)(?:\\s*)([^>]*)(?:>)(.*)(?:</)\\1(?:>)", options: [.caseInsensitive])
	}
	fileprivate static var argumentRegex: NSRegularExpression {
		return try! NSRegularExpression(pattern: "(?:\")?(\\w+)(?:\")?\\s*=\"([^\"]*)\"", options: [])
	}
	
	fileprivate var regularText:String
	fileprivate var attrText:NSAttributedString?
	
	init(text:String) {
		self.regularText = text
	}
	
	func attributedString() -> NSAttributedString {
		if attrText == nil {
			parseText()
		}
		return attrText!
	}
	
	fileprivate func parseText() {
		let srcString = regularText as NSString
		var nextStart = 0
		let outString: NSMutableAttributedString = NSMutableAttributedString()
		HTMLString.basicRegex.enumerateMatches(in: regularText, options: [.reportCompletion], range: NSMakeRange(0, regularText.characters.count))
		{ (result, flags, stop) -> Void in
			guard result != nil else {
				//copy to end of string
				outString.append(NSAttributedString(string: srcString.substring(from: nextStart)))
				return
			}
			let tagName = srcString.substring(with: (result?.rangeAt(1))!)
			let valueString = srcString.substring(with: (result?.rangeAt(3))!)
			var destStr: NSAttributedString?
			switch(tagName) {
				case "b":
					destStr = NSMutableAttributedString(string: valueString)
					(destStr as! NSMutableAttributedString).applyFontTraits(.boldFontMask, range: result!.rangeAt(3))
				case "i":
					destStr = NSMutableAttributedString(string: valueString)
					(destStr as! NSMutableAttributedString).applyFontTraits(.italicFontMask, range: result!.rangeAt(3))
				case "color":
					let content = srcString.substring(with: (result?.rangeAt(2))!)
					let attrs = self.parseColorAttrs(srcString, attrString:srcString.substring(with: (result?.rangeAt(2))!) as NSString)
					destStr = NSAttributedString(string: content, attributes: attrs)
				default:
					os_log("unsupported tag: '%{public}@'", tagName)
					destStr = NSAttributedString(string: srcString.substring(with: (result?.rangeAt(0))!))
			}
			outString.append(destStr!)
			let rng:NSRange = (result?.rangeAt(3))!
			nextStart = rng.location + rng.length
		}
		attrText = NSAttributedString(attributedString: outString)
	}
	
	fileprivate func parseColorAttrs(_ srcString:NSString, attrString:NSString) -> [String:AnyObject] {
		var dict = [String:AnyObject]()
		HTMLString.argumentRegex.enumerateMatches(in: attrString as String, options: [], range: NSMakeRange(0, attrString.length))
		{ (result, flags, stop) -> Void in
			let attrName = srcString.substring(with: (result?.rangeAt(1))!)
			let attrValue = srcString.substring(with: (result?.rangeAt(2))!)
			switch(attrName) {
				case "hex":
					dict[NSForegroundColorAttributeName] = try! PlatformColor(hex: attrValue)
				default:
					os_log("unsupport color attribute '%{public}@'", attrName)
			}
		}
		return dict
	}
}
