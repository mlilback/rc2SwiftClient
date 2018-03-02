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
import PEGKit

open class RCodeHighlighter: BaseHighlighter {
	
	// Get RKeywords from it's file in this bundle:
	let keywords: Set<String> = {
		let bundle = Bundle(for: RCodeHighlighter.self)
		guard let url = bundle.url(forResource: "RKeywords", withExtension: "txt") else {
			fatalError("failed to find RKeywords file")
		}
		// swiftlint:disable:next force_try
		let keyArray = try! NSString(contentsOf: url, encoding: String.Encoding.utf8.rawValue).components(separatedBy: "\n")
		return Set<String>(keyArray)
	}()
	
	override func colorForToken(_ token: PKToken, lastToken: PKToken?, includePreviousCharacter usePrevious:inout Bool) -> PlatformColor? {
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
