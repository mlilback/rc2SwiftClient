//
//  HTMLString.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import MJLLogger

///Class that takes a string of basic html and converts it to an NSAttributedString
/// support tags are: b, i, color(hex="XXXXXX")

open class HTMLString {
	fileprivate static var basicRegex: NSRegularExpression {
		// swiftlint:disable:next force_try
		return try! NSRegularExpression(pattern: "(?:<)(b|color|i)(?:\\s*)([^>]*)(?:>)(.*)(?:</)\\1(?:>)", options: [.caseInsensitive])
	}
	fileprivate static var argumentRegex: NSRegularExpression {
		// swiftlint:disable:next force_try
		return try! NSRegularExpression(pattern: "(?:\")?(\\w+)(?:\")?\\s*=\"([^\"]*)\"", options: [])
	}

	fileprivate var regularText: String
	fileprivate var attrText: NSAttributedString?

	public init(text: String) {
		self.regularText = text
	}

	public func attributedString() -> NSAttributedString {
		if attrText == nil {
			parseText()
		}
		return attrText!
	}

	fileprivate func parseText() {
		let srcString = regularText as NSString
		var nextStart = 0
		let outString: NSMutableAttributedString = NSMutableAttributedString()
		HTMLString.basicRegex.enumerateMatches(in: regularText, options: [.reportCompletion], range: regularText.fullNSRange)
		{ (result, _, _) -> Void in
			guard let result = result else {
				//copy to end of string
				outString.append(NSAttributedString(string: srcString.substring(from: nextStart)))
				return
			}
			if nextStart == 0 {
				outString.append(NSAttributedString(string: srcString.substring(to: result.range.location)))
			} else if result.range.location > nextStart {
				outString.append(NSAttributedString(string: srcString.substring(with: NSRange(location: nextStart, length: result.range.location - nextStart))))
			}
			let tagName = srcString.substring(with: result.range(at: 1))
			let valueString = srcString.substring(with: result.range(at: 3))
			var destStr: NSAttributedString?
			switch tagName {
				case "b", "i":
					destStr = NSMutableAttributedString(string: valueString)
					if let traits = fontTraits(forTag: tagName) {
						(destStr as? NSMutableAttributedString)?.applyFontTraits(traits, range: NSRange(location: 0, length: valueString.count))
					}
				case "color":
//					let content = srcString.substring(with: result.range(at: 2))
					let attrs = self.parseColorAttrs(srcString.substring(with: result.range(at: 2)) as NSString)
					destStr = NSAttributedString(string: valueString, attributes: attrs)
				default:
					Log.warn("unsupported tag: '\(tagName)'", .core)
					destStr = NSAttributedString(string: srcString.substring(with: result.range(at: 0)))
			}
			outString.append(destStr!)
			let rng: NSRange = result.range(at: 0)
			nextStart = rng.location + rng.length
		}
		attrText = NSAttributedString(attributedString: outString)
	}

	public func fontTraits(forTag: String) -> NSFontTraitMask? {
		switch forTag {
		case "b":
			return .boldFontMask
		case "i":
			return .italicFontMask
		default:
			return nil
		}
	}
	
	fileprivate func parseColorAttrs(_ attrString: NSString) -> [NSAttributedStringKey: AnyObject] {
		var dict = [NSAttributedStringKey: AnyObject]()
		HTMLString.argumentRegex.enumerateMatches(in: attrString as String, options: [], range: NSRange(location: 0, length: attrString.length))
		{ (result, _, _) -> Void in
			guard let result = result else { return }
			let attrName = attrString.substring(with: result.range(at: 1))
			let attrValue = attrString.substring(with: result.range(at: 2))
			switch attrName {
				case "hex":
					guard let color = PlatformColor(hexString: attrValue) else {
						Log.warn("Invalid color attribute: \(attrString.substring(with: result.range))", .core)
						return
					}
					dict[NSAttributedStringKey.foregroundColor] = color
				default:
					Log.warn("unsupport color attribute '\(attrName)'", .core)
			}
		}
		return dict
	}
}
