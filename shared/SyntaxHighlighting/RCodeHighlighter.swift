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

public class RCodeHighlighter: CodeHighlighter {
	
	let keywords:Set<String> = {
		let url = NSBundle.mainBundle().URLForResource("RKeywords", withExtension: "txt")!
		let keyArray = try! NSString(contentsOfURL: url, encoding: NSUTF8StringEncoding).componentsSeparatedByString("\n")
		return Set<String>(keyArray)
	}()
	
	override func colorForToken(token:PKToken, lastToken:PKToken?, inout includePreviousCharacter usePrevious:Bool) -> PlatformColor?
	{
		var color:PlatformColor?
		switch(token.tokenType) {
			case .Comment:
				color = colorMap[.Comment]
			case .QuotedString:
				color = colorMap[.Quote]
			case .Number:
				color = PlatformColor.blackColor()
			case .Symbol:
				color = colorMap[.Symbol]
			case .Word:
				if keywords.contains(token.stringValue) {
					color = colorMap[.Keyword]
				}
			default:
				color = nil
		}
		return color
	}
}
