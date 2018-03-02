//
//  BaseHighlighter
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
#if os(OSX)
	import AppKit
#endif
import ClientCore
import ReactiveSwift
import PEGKit

public typealias HighlighterHasHelpCallback = (String) -> Bool

open class BaseHighlighter: NSObject {
	let theme = Property<SyntaxTheme>(ThemeManager.shared.activeSyntaxTheme)
	var helpCallback: HighlighterHasHelpCallback?
	
	public required init(helpCallback: @escaping HighlighterHasHelpCallback) {
		super.init()
		self.helpCallback = helpCallback
	}
	
	/// Subclass should override this to return the color to use and
	/// and if the previous character should be colorized, too (for latex).
	func colorForToken(_ token: PKToken, lastToken: PKToken?,
					   includePreviousCharacter usePrevious:inout Bool)
		-> PlatformColor? {
		preconditionFailure("subclass must override colorForToken")
	}
	
	/// Optional override.
	func addAttributes(_ string: NSMutableAttributedString, range: NSRange) {
	}
	
	func highlightText(_ content: NSMutableAttributedString, range: NSRange) {
		guard range.length > 0 else { return }
		// Add comment attributes:
		content.removeAttribute(.foregroundColor, range: range)
		addAttributes(content, range:range)
		// PEGKit:
		let sourceStr = content.mutableString.substring(with: range)
		let tok = PKTokenizer(string: sourceStr)!
		let slash = Int32("/".unicodeScalars.first!.value)
		let hash = Int32("#".unicodeScalars.first!.value)
		tok.setTokenizerState(tok.symbolState, from: slash, to: slash)
		tok.commentState.reportsCommentTokens = true
		tok.commentState.addSingleLineStartMarker("#")
		tok.symbolState.add("<-")
		tok.symbolState.remove(":-")
		tok.setTokenizerState(tok.commentState, from: hash, to: hash)
		let eof = PKToken.eof().tokenType
		var lastToken: PKToken?
		while let token = tok.nextToken(), token.tokenType != eof {
			var tokenRange = NSRange(location: range.location + Int(token.offset), length: token.stringValue.count)
			var includePrevious: Bool = false
			if let color = colorForToken(token, lastToken: lastToken, includePreviousCharacter: &includePrevious)
			{
				if includePrevious {
					tokenRange.location -= 1
					tokenRange.length += 1
				}
				content.addAttribute(.foregroundColor, value: color, range: tokenRange)
			}
			if token.tokenType == .word, helpCallback?(token.stringValue) ?? false {
				// add tag marking as having help
				content.addAttribute(.link, value: "help:\(token.stringValue!)", range: tokenRange)
			}
			lastToken = token
		}
	}
}
