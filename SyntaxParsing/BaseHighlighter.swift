//
//  BaseHighlighter
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
#if os(OSX)
	import AppKit
#endif
import Rc2Common
import ReactiveSwift
import PEGKit

public typealias HasHelpCallback = (String) -> Bool

//extension NSAttributedStringKey {
//	public static let rc2code: NSAttributedStringKey
//}

open class BaseHighlighter: NSObject {
	let theme = Property<SyntaxTheme>(ThemeManager.shared.activeSyntaxTheme)
	var helpCallback: HasHelpCallback?
	
	// Get RKeywords from it's file in this bundle:
	static let rKeywords: Set<String> = {
		let bundle = Bundle(for: BaseHighlighter.self)
		guard let url = bundle.url(forResource: "RKeywords", withExtension: "txt")
			else { fatalError("failed to find RKeywords file")
		}
		// swiftlint:disable:next force_try
		let keyArray = try! NSString(contentsOf: url, encoding: String.Encoding.utf8.rawValue).components(separatedBy: "\n")
		return Set<String>(keyArray)
	}()
	
	/// keywords used by this highlighter. property to eventually allow for different sets of keywords
	public let keywords: Set<String>
	
	public required init(helpCallback: @escaping HasHelpCallback) {
		keywords = BaseHighlighter.rKeywords
		super.init()
		self.helpCallback = helpCallback
	}
	
	/// Optional override.
	func addAttributes(_ string: NSMutableAttributedString, range: NSRange) {
	}
	
	
	func highlightText(_ attribStr: NSMutableAttributedString, chunk: DocumentChunk) {
		highlightText(attribStr, range: chunk.parsedRange, chunk: chunk)
	}
	
	func highlightText(_ aStr: NSMutableAttributedString, range: NSRange, chunk: ChunkProtocol) {
		guard range.length > 0 else { return }
		aStr.removeAttribute(.foregroundColor, range: range)
		// PEGKit:
		let swiftStr = aStr.mutableString.substring(with: range)
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
			let color = colorForToken(token, lastToken: lastToken,
									  includePreviousCharacter: &includePrevious,
									  chunk: chunk)
			if includePrevious {	//>>> check
				tokenRange.location -= 1
				tokenRange.length += 1
			}
			aStr.addAttribute(.foregroundColor, value: color, range: tokenRange)
			if token.tokenType == .word, helpCallback?(token.stringValue) ?? false {
				// add tag marking as having help
				aStr.addAttribute(.link, value: "help:\(token.stringValue!)", range: tokenRange)
			}
			lastToken = token
		}
	}
	
	func colorForToken(_ token: PKToken, lastToken: PKToken?,
					   includePreviousCharacter usePrevious:inout Bool,
					   chunk: ChunkProtocol)
		-> PlatformColor
	{
//=		var color = PlatformColor.black // nil
		var out = theme.value.color(for: .quote)
		if token.isQuotedString {
			return out
		}
		else if token.stringValue == "\"" {
			return out
		}
		switch token.tokenType {
		case .comment:
			out = theme.value.color(for: .comment)
		case .quotedString:
			out = theme.value.color(for: .quote)
		case .number:
			out = PlatformColor.black
		case .symbol:	// a bug in PEGKit?!
			out = theme.value.color(for: .symbol)
		case .word:
			if chunk.chunkType == .code && keywords.contains(token.stringValue) {
				out = theme.value.color(for: .keyword)
			}
			else if chunk.docType == .latex || chunk.chunkType == .equation {
				if lastToken?.tokenType == .symbol && lastToken?.stringValue.first == "\\" {
					usePrevious = true
					out = theme.value.color(for: .keyword)
				}
			}
		default:
			out = PlatformColor.black
		}
		return out
	}
}

