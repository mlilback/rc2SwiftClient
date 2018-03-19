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

public typealias HasHelpCallback = (String) -> Bool

open class BaseHighlighter: NSObject {
	let theme = Property<SyntaxTheme>(ThemeManager.shared.activeSyntaxTheme)
	var helpCallback: HasHelpCallback?
	
	// Get RKeywords from it's file in this bundle:
	let keywords: Set<String> = {
		let bundle = Bundle(for: BaseHighlighter.self)
		guard let url = bundle.url(forResource: "RKeywords", withExtension: "txt")
			else { fatalError("failed to find RKeywords file")
		}
		// swiftlint:disable:next force_try
		let keyArray = try! NSString(contentsOf: url, encoding: String.Encoding.utf8.rawValue).components(separatedBy: "\n")
		return Set<String>(keyArray)
	}()
	
	public required init(helpCallback: @escaping HasHelpCallback) {
		super.init()
		self.helpCallback = helpCallback
	}
	
	/// Optional override.
	func addAttributes(_ string: NSMutableAttributedString, range: NSRange) {
	}
	
	func highlightText(_ attribStr: NSMutableAttributedString, chunk: DocumentChunk) {
		let range = chunk.parsedRange
		guard range.length > 0 else { return }
		attribStr.removeAttribute(.foregroundColor, range: range)
		// PEGKit:
		let swiftStr = attribStr.mutableString.substring(with: range)
		let tok = PKTokenizer(string: swiftStr)!
		setBaseTokenizer(tok)
		// Comments tags:
		tok.setTokenizerState(tok.commentState, from: hashChar, to: hashChar)
		tok.commentState.addSingleLineStartMarker("#")
		tok.setTokenizerState(tok.commentState, from:percentChar, to:percentChar)
		tok.commentState.addSingleLineStartMarker("%")
		tok.setTokenizerState(tok.commentState, from:lessChar, to:lessChar)
		tok.commentState.addMultiLineStartMarker("<!--", endMarker:"-->")
		tok.setTokenizerState(tok.commentState, from:backSlashChar, to:backSlashChar)
		tok.commentState.addMultiLineStartMarker("\\begin{comment}", endMarker:"\\end{comment}")
		tok.commentState.addMultiLineStartMarker("\\iffalse", endMarker:"\\fi")
		tok.symbolState.remove("\"")
		tok.symbolState.remove("\'")
		
		let eof = PKToken.eof().tokenType
		var lastToken: PKToken?
		while let token = tok.nextToken(), token.tokenType != eof {
			var tokenRange = NSRange(location: range.location + Int(token.offset),
									 length: token.stringValue.count)
			var includePrevious: Bool = false
			if let color = colorForToken(token, lastToken: lastToken,
										 includePreviousCharacter: &includePrevious,
										 chunk: chunk) {
				if includePrevious {	//>>> check
					tokenRange.location -= 1
					tokenRange.length += 1
				}
				attribStr.addAttribute(.foregroundColor, value: color, range: tokenRange)
			}
			if token.tokenType == .word, helpCallback?(token.stringValue) ?? false {
				// add tag marking as having help
				attribStr.addAttribute(.link, value: "help:\(token.stringValue!)", range: tokenRange)
			}
			lastToken = token
		}
	}
	
	func colorForToken(_ token: PKToken, lastToken: PKToken?,
					   includePreviousCharacter usePrevious:inout Bool,
					   chunk: DocumentChunk)
		-> PlatformColor?
	{
		var color: PlatformColor = PlatformColor.black // nil
		if token.isQuotedString {
			return theme.value.color(for: .quote)
		}
		else if token.stringValue == "\"" {
			return theme.value.color(for: .quote)
		}
		switch token.tokenType {
		case .comment:
			color = theme.value.color(for: .comment)
		case .quotedString:
			color = theme.value.color(for: .quote)
		case .number:
			color = PlatformColor.black
		case .symbol:	// a bug in PEGKit?!
			color = theme.value.color(for: .symbol)
		case .word:
			if chunk.chunkType == .code && keywords.contains(token.stringValue) {
				color = theme.value.color(for: .keyword)
			}
			else if chunk.docType == .latex || chunk.chunkType == .equation {
				if lastToken?.tokenType == .symbol && lastToken?.stringValue.first == "\\" {
					usePrevious = true
					color = theme.value.color(for: .keyword)
				}
			}
		default:
			color = PlatformColor.black // nil
		}
		return color
	}
}

