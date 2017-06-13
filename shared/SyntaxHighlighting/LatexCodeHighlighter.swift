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

open class LatexCodeHighlighter: CodeHighlighter {
	let commentRegex: NSRegularExpression
	
	override init()  {
		// swiftlint:disable:next force_try
		self.commentRegex = try! NSRegularExpression(pattern: "(?<!\\\\)(%.*\n)", options: [])
		super.init()
	}
	
	override func addAttributes(_ content: NSMutableAttributedString, range: NSRange) {
		let color = theme.value.color(for: .comment)
		let sourceStr = content.mutableString.substring(with: range)
		commentRegex.enumerateMatches(in: sourceStr, options: [], range: NSRange(location: 0, length: sourceStr.characters.count))
		{ (results, _, _) -> Void in
			content.addAttribute(NSForegroundColorAttributeName, value: color, range: (results?.rangeAt(1))!)
		}
	}
	
	override func colorForToken(_ token: PKToken, lastToken: PKToken?, includePreviousCharacter usePrevious:inout Bool) -> PlatformColor?
	{
		var color: PlatformColor?
		switch token.tokenType  {
		case .comment:
			color = theme.value.color(for: .comment)
		case .quotedString:
			color = theme.value.color(for: .quote)
		case .symbol:
			color = theme.value.color(for: .symbol)
		case .word:
			if lastToken?.tokenType == .symbol && lastToken?.stringValue.characters.first == "\\"
			{
				usePrevious = true
				color = theme.value.color(for: .keyword)
			}
		default:
			color = nil
		}
		return color
	}
}
