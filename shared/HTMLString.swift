//
//  HTMLString.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

///Class that takes a string of basic html and converts it to an NSAttributedString
/// support tags are: b, i, color(hex="XXXXXX")

public class HTMLString {
	private static var basicRegex: NSRegularExpression {
		return try! NSRegularExpression(pattern: "(?:<)(b|color)(?:\\s*)([^>]*)(?:>)(.*)(?:</)\\1(?:>)", options: [.CaseInsensitive])
	}
	private static var argumentRegex: NSRegularExpression {
		return try! NSRegularExpression(pattern: "(?:\")?(\\w+)(?:\")?\\s*=\"([^\"]*)\"", options: [])
	}
	
	private var regularText:String
	private var attrText:NSAttributedString?
	
	init(text:String) {
		self.regularText = text
	}
	
	func attributedString() -> NSAttributedString {
		if attrText == nil {
			parseText()
		}
		return attrText!
	}
	
	private func parseText() {
		let srcString = regularText as NSString
		var nextStart = 0
		let outString: NSMutableAttributedString = NSMutableAttributedString()
		HTMLString.basicRegex.enumerateMatchesInString(regularText, options: [.ReportCompletion], range: NSMakeRange(0, regularText.characters.count))
		{ (result, flags, stop) -> Void in
			guard result != nil else {
				//copy to end of string
				outString.appendAttributedString(NSAttributedString(string: srcString.substringFromIndex(nextStart)))
				return
			}
			let tagName = srcString.substringWithRange((result?.rangeAtIndex(1))!)
			let valueString = srcString.substringWithRange((result?.rangeAtIndex(3))!)
			var destStr: NSAttributedString?
			switch(tagName) {
				case "b":
					destStr = NSMutableAttributedString(string: valueString)
					(destStr as! NSMutableAttributedString).applyFontTraits(.BoldFontMask, range: result!.rangeAtIndex(3))
				case "i":
					destStr = NSMutableAttributedString(string: valueString)
					(destStr as! NSMutableAttributedString).applyFontTraits(.ItalicFontMask, range: result!.rangeAtIndex(3))
				case "color":
					let content = srcString.substringWithRange((result?.rangeAtIndex(2))!)
					let attrs = self.parseColorAttrs(srcString, attrString:srcString.substringWithRange((result?.rangeAtIndex(2))!))
					destStr = NSAttributedString(string: content, attributes: attrs)
				default:
					log.warning("unsupported tag: '\(tagName)'")
					destStr = NSAttributedString(string: srcString.substringWithRange((result?.rangeAtIndex(0))!))
			}
			outString.appendAttributedString(destStr!)
			let rng:NSRange = (result?.rangeAtIndex(3))!
			nextStart = rng.location + rng.length
		}
		attrText = NSAttributedString(attributedString: outString)
	}
	
	private func parseColorAttrs(srcString:NSString, attrString:NSString) -> [String:AnyObject] {
		var dict = [String:AnyObject]()
		HTMLString.argumentRegex.enumerateMatchesInString(attrString as String, options: [], range: NSMakeRange(0, attrString.length))
		{ (result, flags, stop) -> Void in
			let attrName = srcString.substringWithRange((result?.rangeAtIndex(1))!)
			let attrValue = srcString.substringWithRange((result?.rangeAtIndex(2))!)
			switch(attrName) {
				case "hex":
					dict[NSForegroundColorAttributeName] = try! PlatformColor(hex: attrValue)
				default:
					log.warning("unsupport color attribute '\(attrName)'")
			}
		}
		return dict
	}
}
