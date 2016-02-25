//
//  LatexCodeHighlighter
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
#if os(OSX)
	import AppKit
#endif
import PEGKit

class LatexCodeHighlighter : CodeHighlighter {
	let commentRegex:NSRegularExpression
	
	override init()  {
		self.commentRegex = try! NSRegularExpression(pattern: "(?<!\\\\)(%.*\n)", options: [])
		super.init()
	}
	
	override func addAttributes(content:NSMutableAttributedString, range:NSRange) {
		if let color = colorMap[.Comment] {
			let sourceStr = content.string.substringWithRange(range.toStringRange(content.string)!)
			commentRegex.enumerateMatchesInString(sourceStr, options: [], range: NSMakeRange(0, sourceStr.characters.count))
			{ (results, _, _) -> Void in
				content.addAttribute(NSForegroundColorAttributeName, value: color, range: (results?.rangeAtIndex(1))!)
			}
		}
	}
	
	override func colorForToken(token:PKToken, lastToken:PKToken?, inout includePreviousCharacter usePrevious:Bool) -> PlatformColor?
	{
		var color:PlatformColor?
		switch(token.tokenType) {
		case .Comment:
			color = colorMap[.Comment]
		case .QuotedString:
			color = colorMap[.Quote]
		case .Symbol:
			color = colorMap[.Symbol]
		case .Word:
			if lastToken?.tokenType == .Symbol && lastToken?.stringValue.characters.first == "\\"
			{
				usePrevious = true
				color = colorMap[.Keyword]
			}
		default:
			color = nil
		}
		return color
	}
}
