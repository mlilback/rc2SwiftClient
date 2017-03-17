//
//  RCodeHighlighter
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
#if os(OSX)
	import AppKit
#endif
import ClientCore

let RCodeHighlighterColors = "RCodeHighlighterColors"

open class RCodeHighlighter: CodeHighlighter {
	
	let keywords: Set<String> = {
		let url = Bundle.main.url(forResource: "RKeywords", withExtension: "txt")!
		// swiftlint:disable:next force_try
		let keyArray = try! NSString(contentsOf: url, encoding: String.Encoding.utf8.rawValue).components(separatedBy: "\n")
		return Set<String>(keyArray)
	}()
	
	override func colorForToken(_ token: PKToken, lastToken: PKToken?, includePreviousCharacter usePrevious:inout Bool) -> PlatformColor?
	{
		var color: PlatformColor?
		switch token.tokenType {
			case .comment:
				color = theme.value.color(for: .comment)
			case .quotedString:
				color = theme.value.color(for: .quote)
			case .number:
				color = PlatformColor.black
			case .symbol:
				color = theme.value.color(for: .symbol)
			case .word:
				if keywords.contains(token.stringValue) {
					color = theme.value.color(for: .keyword)
				}
			default:
				color = nil
		}
		return color
	}
}
