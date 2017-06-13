//
//  CodeHighlighter
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
#if os(OSX)
	import AppKit
#endif
import ClientCore
import ReactiveSwift

open class CodeHighlighter: NSObject {
	let theme = Property<SyntaxTheme>(ThemeManager.shared.activeSyntaxTheme)
	
	override public init() {
		super.init()
	}
	
	///subclass should override this to return the color to use and if the previous character should be colorized, too (for latex)
	func colorForToken(_ token: PKToken, lastToken: PKToken?, includePreviousCharacter usePrevious:inout Bool) -> PlatformColor?
	{
		preconditionFailure("subclass must override highlightText")
	}
	
	///should not manipulate the string, only attributes
	func addAttributes(_ string: NSMutableAttributedString, range: NSRange) {
		
	}
	
	func highlightText(_ content: NSMutableAttributedString, range: NSRange) {
		guard range.length > 0 else { return }
		content.removeAttribute(NSForegroundColorAttributeName, range: range)
		addAttributes(content, range:range)
		let sourceStr = content.mutableString.substring(with: range)

		let tokenizer = PKTokenizer(string: sourceStr)!
		let slash = Int32("/".unicodeScalars.first!.value)
		let hash = Int32("#".unicodeScalars.first!.value)
		tokenizer.setTokenizerState(tokenizer.symbolState, from: slash, to: slash)
		tokenizer.commentState.reportsCommentTokens = true
		tokenizer.commentState.addSingleLineStartMarker("#")
		tokenizer.commentState.reportsCommentTokens = true
		tokenizer.symbolState.add("<-")
		tokenizer.symbolState.remove(":-")
		tokenizer.setTokenizerState(tokenizer.commentState, from: hash, to: hash)
		let eof = PKToken.eof().tokenType
		var lastToken: PKToken?
		while let token = tokenizer.nextToken(), token.tokenType != eof {
			var tokenRange = NSRange(location: range.location + Int(token.offset), length: token.stringValue.characters.count)
			var includePrevious: Bool = false
			if let color = colorForToken(token, lastToken: lastToken, includePreviousCharacter: &includePrevious)
			{
				if includePrevious {
					tokenRange.location -= 1
					tokenRange.length += 1
				}
				content.addAttribute(NSForegroundColorAttributeName, value: color, range: tokenRange)
				
			}
			if token.tokenType == .word && HelpController.shared.hasTopic(token.stringValue) {
				//add tag marking as having help
				content.addAttribute(NSLinkAttributeName, value: "help:\(token.stringValue!)", range: tokenRange)
			}
			lastToken = token
		}
	}
}
