//
//  CodeHighlighter
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import PEGKit
#if os(OSX)
	import AppKit
#endif

class CodeHighlighter: NSObject {
	let colorMap:SyntaxColorMap = { return SyntaxColorMap.standardMap }()
	
	///subclass should override this to return the color to use and if the previous character should be colorized, too (for latex)
	func colorForToken(token:PKToken, lastToken:PKToken?, inout includePreviousCharacter usePrevious:Bool) -> PlatformColor?
	{
		preconditionFailure("subclass must override highlightText")
	}
	
	///should not manipulate the string, only attributes
	func addAttributes(string:NSMutableAttributedString, range:NSRange) {
		
	}
	
	func highlightText(content:NSMutableAttributedString, range:NSRange) {
		content.removeAttribute(NSForegroundColorAttributeName, range: range)
		addAttributes(content, range:range)
		let sourceStr = content.string.substringWithRange(range.toStringRange(content.string)!)

		let tokenizer = PKTokenizer(string: sourceStr)
		let slash = Int32("/".unicodeScalars.first!.value)
		let hash = Int32("#".unicodeScalars.first!.value)
		tokenizer.setTokenizerState(tokenizer.symbolState, from: slash, to: slash)
		tokenizer.commentState.reportsCommentTokens = true
		tokenizer.commentState.addSingleLineStartMarker("#")
		tokenizer.commentState.reportsCommentTokens = true
		tokenizer.symbolState.add("<-")
		tokenizer.symbolState.remove(":-")
		tokenizer.setTokenizerState(tokenizer.commentState, from: hash, to: hash)
		let eof = PKToken.EOFToken().tokenType
		var lastToken:PKToken?
		while let token = tokenizer.nextToken() where token.tokenType != eof {
			var tokenRange = NSMakeRange(range.location + Int(token.offset), token.stringValue.characters.count)
			var includePrevious:Bool = false
			if let color = colorForToken(token, lastToken: lastToken, includePreviousCharacter: &includePrevious)
			{
				if includePrevious {
					tokenRange.location -= 1
					tokenRange.length += 1
				}
				content.addAttribute(NSForegroundColorAttributeName, value: color, range: tokenRange)
				
			}
			lastToken = token
		}
	}
}
