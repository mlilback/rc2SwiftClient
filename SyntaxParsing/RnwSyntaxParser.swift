//
//  RnwSyntaxParser
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
#if os(OSX)
	import AppKit
#endif
//- import Model
import PEGKit

enum RnwParserState : Int {
	case sea, eqBlock, codePossible, codeBlock
}

class RnwSyntaxParser: BaseSyntaxParser {
	
	override func parseRange(_ fullRange: NSRange) {
		chunks.removeAll(); chunks = [DocumentChunk]()
		var chunkIndex = 1
		// PEG Kit:
		let tok = PKTokenizer(string: textStorage.string)!
		tok.whitespaceState.reportsWhitespaceTokens = true
		tok.numberState.allowsScientificNotation = true	// good in general
		tok.commentState.reportsCommentTokens = true
		// Order of $$ before $ matters:
		tok.symbolState.add("$$")	// eqBlock begin, end
		tok.symbolState.add("<<")	// codePossible
		tok.symbolState.add(">>=")	// codeBlock definite
		tok.symbolState.add("@")	// codeBlock end
		let eof = PKToken.eof().tokenType
		var state = RnwParserState.sea	// sea - docs chunk
		var seaBegin:Int = 0, seaEnd:Int = 0
		var token = tok.nextToken()!
		var tokenLast = token
		var closeChunk = false
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
			if (state == .sea || state == .codePossible) {
				if token.stringValue == "$$" {
					currType = (.equation, .display)
					state = .eqBlock
					closeChunk = true }
				else if token.stringValue == "<<" {
					state = .codePossible
					seaEnd = Int(token.offset) }
				else if token.stringValue == ">>=" && state == .codePossible {
					currType = (.code, .none)
					closeChunk = true
				}
				// Create a chunk after switching states:
				if closeChunk {
					if state == .codePossible { state = .codeBlock }
					else { seaEnd = Int(token.offset) }
					let range = NSMakeRange(seaBegin, seaEnd-seaBegin)
					chunks.append(DocumentChunk(chunkType: .docs, equationType: .none,
												range: range, chunkNumber: chunkIndex))
					chunkIndex += 1; closeChunk = false
				}
			// Switch close state based on symbols:
			} else if state == .codeBlock && token.stringValue == "@" {
				closeChunk = true
			} else if state == .eqBlock   && token.stringValue == "$$"{
				closeChunk = true
			}
			// Create a chunk after switching states:
			tokenLast = token
			if closeChunk {
				token = tok.nextToken()!
				seaBegin = Int(token.offset)
				let range = NSMakeRange(seaEnd, seaBegin-seaEnd)
				chunks.append(DocumentChunk(chunkType: currType.0, equationType: currType.1,
											range: range, chunkNumber: chunkIndex))
				state = .sea; chunkIndex += 1; closeChunk = false
				currType = (.docs, .none)
			}
			else {
				token = tok.nextToken()!
			}
		}
		// Handle end cases:
		if state == .sea && Int(tokenLast.offset) > seaBegin {
			let range = NSMakeRange(seaBegin, Int(tokenLast.offset)-seaBegin)
			chunks.append(DocumentChunk(chunkType: .docs, equationType: .none,
										range: range, chunkNumber: chunkIndex))
		} else if Int(token.offset) > seaEnd {
			let range = NSMakeRange(seaEnd, Int(tokenLast.offset)-seaEnd)
			chunks.append(DocumentChunk(chunkType: currType.0, equationType: currType.1,
										range: range, chunkNumber: chunkIndex))
		}
		
		for c in chunks {
			print("num=\(c.chunkNumber), range=\(c.parsedRange), type=\(c.chunkType)")
		}
		
		colorChunks(chunks)
	}
}
