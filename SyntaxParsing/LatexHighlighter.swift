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
import PEGKit

open class LatexHighlighter: BaseHighlighter {
	let commentRegex: NSRegularExpression
	
	required public init(helpCallback: @escaping HighlighterHasHelpCallback)  {
		// swiftlint:disable:next force_try
		self.commentRegex = try! NSRegularExpression(pattern: "(?<!\\\\)(%.*\n)", options: [])
		super.init(helpCallback: helpCallback)
	}
	
	override func addAttributes(_ content: NSMutableAttributedString, range: NSRange) {
		let color = theme.value.color(for: .comment)
		let str = content.mutableString.substring(with: range)
		commentRegex.enumerateMatches(in: str, options: [],
									  range: NSRange(location: 0, length: str.count))
		{ (results, _, _) -> Void in
			content.addAttribute(.foregroundColor, value: color, range: (results?.range(at:1))!)
		}
	}
	
	override func colorForToken(_ token: PKToken, lastToken: PKToken?, includePreviousCharacter usePrevious:inout Bool) -> PlatformColor? {
		var color: PlatformColor?
		switch token.tokenType  {
		case .comment:
			color = theme.value.color(for: .comment)
		case .quotedString:
			color = theme.value.color(for: .quote)
		case .symbol:
			color = theme.value.color(for: .symbol)
		case .word:
			if lastToken?.tokenType == .symbol && lastToken?.stringValue.first == "\\" {
				usePrevious = true
				color = theme.value.color(for: .keyword)
			}
		default:
			color = nil
		}
		return color
	}
}
