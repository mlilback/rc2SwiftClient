//
//  RmdSyntaxParser
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
#if os(OSX)
	import AppKit
#endif
import PEGKit

private enum RmdParserState : Int {
	case sea, codeBlock, codeIn, eqBlock, eqIn, eqPossible
}

class RmdSyntaxParser: BaseSyntaxParser {
	
	override func parseRange(_ range: NSRange) {
		chunks.removeAll(); chunks = [DocumentChunk]()
		var chunkIndex = 1
		// PEG Kit:
		let tok = PKTokenizer(string: textStorage.string)!
		tok.whitespaceState.reportsWhitespaceTokens = true
		tok.numberState.allowsScientificNotation = true	// good in general
		tok.commentState.reportsCommentTokens = true
		// Order of ``` before ` matters:
		tok.symbolState.add("```")		// codeBlock begin, end
		tok.symbolState.add("`")		// codeIn begin, end
		tok.symbolState.add("$$")		// eqBlock begin, end
		tok.symbolState.add("$")		// eqIn begin, end
		tok.symbolState.add("<math")	// eqPossible
		tok.symbolState.add(">")		// eqBlock mathML definite
		tok.symbolState.add("</math>")	// eqBlock mathML end
		let eof = PKToken.eof().tokenType
		var state = RmdParserState.sea	// sea - docs chunk
		var seaBegin:Int = 0, seaEnd:Int = 0
		var token = tok.nextToken()!
		var tokenLast = token
		var closeChunk = false
		// Reference:
		//		public enum ChunkType {
		//			case docs, code, equation
		//		public enum EquationType: String {
		//			case invalid, inline, display, mathML = "MathML"
		var currType:(ChunkType, EquationType) = (.docs, .none)
		// Parse by loop through tokens and changing states:
		while token.tokenType != eof {
			// Ignore everything but predefined chunk-defining symbols:
			if token.tokenType != .symbol {
				tokenLast = token
				token = tok.nextToken()!
				continue
			}
			// Switch open state based on symbols:
			if state == .sea || state == .eqPossible {
				if token.stringValue == "```" {
					currType = (.code, .none)
					state = .codeBlock
					closeChunk = true }
				else if token.stringValue == "`" {
					currType = (.code, .none)
					state = .codeIn
					closeChunk = true }
				else if token.stringValue == "$$" {
					currType = (.equation, .display)
					state = .eqBlock
					closeChunk = true }
				else if token.stringValue == "$" {
					currType = (.equation, .inline)
					state = .eqIn
					closeChunk = true }
				else if token.stringValue == "<math" {
					state = .eqPossible
					seaEnd = Int(token.offset) }
				else if token.stringValue == ">" && state == .eqPossible {
					currType = (.equation, .mathML)
					closeChunk = true
				}
				// Create a chunk after switching states:
				if closeChunk {
					if state == .eqPossible { state = .eqBlock }
					else { seaEnd = Int(token.offset) }
					let range = NSMakeRange(seaBegin, seaEnd-seaBegin)
					chunks.append(DocumentChunk(chunkType: .docs, equationType: .none,
												range: range, chunkNumber: chunkIndex))
					chunkIndex += 1; closeChunk = false
				}
			}
			// Switch close state based on symbols:
			else if state == .codeIn    && token.stringValue == "`" {
				closeChunk = true }
			else if state == .codeBlock && token.stringValue == "```"{
				closeChunk = true }
			else if state == .eqIn      && token.stringValue == "$"{
				closeChunk = true }
			else if state == .eqBlock   && token.stringValue == "$$"{
				closeChunk = true }
			else if state == .eqBlock   && token.stringValue == "</math>"{
				closeChunk = true
			}
			// Create a chunk after switching states:
			tokenLast = token
			if closeChunk {
				token = tok.nextToken()!
				seaBegin = Int(token.offset)
				let range = NSMakeRange(seaEnd, seaBegin-seaEnd)
				if seaBegin - Int(tokenLast.offset) > 0 {
					chunks.append(DocumentChunk(chunkType: currType.0, equationType: currType.1,
											range: range, chunkNumber: chunkIndex))
				}
				state = .sea; chunkIndex += 1; closeChunk = false
				currType = (.docs, .none)
			}
			else {
				token = tok.nextToken()!
			}
		}
		// Handle end cases:
		if state == .sea && Int(tokenLast.offset) > seaBegin {
			if seaBegin - Int(tokenLast.offset)-seaBegin > 0 {
				let range = NSMakeRange(seaBegin, Int(tokenLast.offset)-seaBegin)
				chunks.append(DocumentChunk(chunkType: .docs, equationType: .none,
											range: range, chunkNumber: chunkIndex))
			}
		} else if Int(token.offset) > seaEnd {
			if seaEnd - Int(tokenLast.offset)-seaEnd > 0 {
				let range = NSMakeRange(seaEnd, Int(tokenLast.offset)-seaEnd)
				chunks.append(DocumentChunk(chunkType: currType.0, equationType: currType.1,
											range: range, chunkNumber: chunkIndex))
			}
		}

//		for c in chunks {
//			print("num=\(c.chunkNumber)\t range=\(c.parsedRange)\t type=\(c.chunkType)")
//		}
	}
}
