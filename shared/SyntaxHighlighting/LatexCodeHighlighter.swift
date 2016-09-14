//
//  LatexCodeHighlighter
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
#if os(OSX)
	import AppKit
#endif
import ClientCore

open class LatexCodeHighlighter : CodeHighlighter {
	let commentRegex:NSRegularExpression
	
	override init()  {
		self.commentRegex = try! NSRegularExpression(pattern: "(?<!\\\\)(%.*\n)", options: [])
		super.init()
	}
	
	override func addAttributes(_ content:NSMutableAttributedString, range:NSRange) {
		if let color = colorMap[.Comment] {
			let sourceStr = content.string.substring(with: range.toStringRange(content.string)!)
			commentRegex.enumerateMatches(in: sourceStr, options: [], range: NSMakeRange(0, sourceStr.characters.count))
			{ (results, _, _) -> Void in
				content.addAttribute(NSForegroundColorAttributeName, value: color, range: (results?.rangeAt(1))!)
			}
		}
	}
	
	override func colorForToken(_ token:PKToken, lastToken:PKToken?, includePreviousCharacter usePrevious:inout Bool) -> PlatformColor?
	{
		var color:PlatformColor?
		switch(token.tokenType) {
		case .comment:
			color = colorMap[.Comment]
		case .quotedString:
			color = colorMap[.Quote]
		case .symbol:
			color = colorMap[.Symbol]
		case .word:
			if lastToken?.tokenType == .symbol && lastToken?.stringValue.characters.first == "\\"
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
