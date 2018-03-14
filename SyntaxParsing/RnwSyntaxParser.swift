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
	case sea, eqBlock, eqIn, codePossible, codeBlock
}

class RnwSyntaxParser: BaseSyntaxParser {
	
	override func parseRange(_ fullRange: NSRange) {
		// Clear and reinit chunks:
		chunks.removeAll()
		chunks = [DocumentChunk](); var chunkIndex = 1
		// PEG Kit:
		let tok = PKTokenizer(string: textStorage.string)!
		setBaseTokenizer(tok)
		tok.setTokenizerState(tok.commentState, from:percentChar, to:percentChar)
		tok.commentState.addSingleLineStartMarker("%")
		tok.setTokenizerState(tok.commentState, from:backSlashChar, to:backSlashChar)
		tok.commentState.addMultiLineStartMarker("\\begin{comment}", endMarker:"\\end{comment}")
		tok.commentState.addMultiLineStartMarker("\\iffalse", endMarker:"\\fi")
		// Order of $$ before $ matters:
		tok.symbolState.add("$$")	// eqBlock begin, end
		tok.symbolState.add("$")	// eqIn begin, end
		tok.symbolState.add("<<")	// codePossible
		tok.symbolState.add(">>=")	// codeBlock definite
		tok.symbolState.add("@")	// codeBlock end
		let eof = PKToken.eof().tokenType
		var state = RnwParserState.sea	// sea - docs chunk
		var begin:Int = 0, end:Int = 0
		var token = tok.nextToken()!
		var closeChunk = false
		var currType:(ChunkType, EquationType) = (.latex, .none)
		var newType = currType
		var ch:DocumentChunk
		// Parse by loop through tokens and changing states:
		while token.tokenType != eof {
			// Ignore everything but predefined chunk-defining symbols:
			if token.tokenType != .symbol {
				token = tok.nextToken()!
				continue
			}
			// Switch open state based on symbols:
			if (state == .sea || state == .codePossible) {
				if token.stringValue == "$$" {
					newType = (.equation, .multiLine); state = .eqBlock
					closeChunk = true }
				else if token.stringValue == "$" {
					newType = (.equation, .inline); state = .eqIn
					closeChunk = true }
				else if token.stringValue == "<<" {
					state = .codePossible
					end = Int(token.offset) }
				else if token.stringValue == ">>=" && state == .codePossible {
					newType = (.code, .none)
					closeChunk = true
				}
				// Create a chunk after switching states:
				if closeChunk {
					if state == .codePossible { state = .codeBlock }
					else { end = Int(token.offset) }
					if end > fullRange.length { end = fullRange.length }
					if end-begin > 0 {
						let range = NSMakeRange(begin, end-begin)
						ch = DocumentChunk(chunkType: currType.0, equationType: currType.1,
										   range: range, chunkNumber: chunkIndex)
						chunks.append(ch); chunkIndex += 1
					}
					currType = newType; begin = end
					closeChunk = false
				}
			}
				// Switch close state based on symbols:
			else if state == .codeBlock && token.stringValue == "@" {
				closeChunk = true }
			else if state == .eqBlock   && token.stringValue == "$$"{
				closeChunk = true }
			else if state == .eqIn   	&& token.stringValue == "$"{
				closeChunk = true
			}
			// Create a chunk after switching states:
			token = tok.nextToken()!
			if closeChunk {
				if (token.tokenType == eof) { end = fullRange.length }
				else { end = Int(token.offset) }
				if end > fullRange.length { end = fullRange.length }
				if end-begin > 2 { // has to have at least 3 chars, including ends
					let fullRange = NSMakeRange(begin, end-begin)
					ch = DocumentChunk(chunkType: currType.0, equationType: currType.1,
									   range: fullRange, chunkNumber: chunkIndex)
					chunks.append(ch); chunkIndex += 1
					begin = end
				}
				currType = (.latex, .none)
				closeChunk = false; state = .sea
			}
		}
		// Handle end cases:
		end = fullRange.length
		if end > begin {
			let fullRange = NSMakeRange(begin, end-begin)
			chunks.append(DocumentChunk(chunkType: currType.0, equationType: currType.1,
										range: fullRange, chunkNumber: chunkIndex))
		}
	}
}

