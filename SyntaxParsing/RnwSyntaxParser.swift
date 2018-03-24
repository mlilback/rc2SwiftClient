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
		var beginInner:Int = 0, endInner:Int = 0
		var beginOff:Int = 0, endOff:Int = 0
		
		var token = tok.nextToken()!
		// TODO: add FrontMatter for LaTex
		
		var closeChunk = false
		var currType:(ChunkType, DocType, EquationType) = (.docs, .latex, .none)
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
					newType = (.equation, .none, .display); state = .eqBlock
					beginOff = 2; closeChunk = true }
				else if token.stringValue == "$" {
					newType = (.equation, .none, .inline); state = .eqIn
					beginOff = 1; closeChunk = true }
				else if token.stringValue == "<<" {
					state = .codePossible
					end = Int(token.offset) }
				else if token.stringValue == ">>=" && state == .codePossible {
					newType = (.code, .none, .none)
					beginInner = Int(token.offset) + 3
					closeChunk = true
				}
				// Create a chunk after switching states:
				if closeChunk {
					if state == .codePossible { state = .codeBlock }
					else { end = Int(token.offset) }
					if end > fullRange.length { end = fullRange.length }
					if end-begin > 0 {
						let range = NSMakeRange(begin, end-begin)
						ch = DocumentChunk(chunkType: currType.0, docType: currType.1,
										   equationType: currType.2, range: range,
										   innerRange: range, chunkNumber: chunkIndex)
						chunks.append(ch); chunkIndex += 1
						begin = end
					}
					currType = newType
					closeChunk = false
				}
			}
				// Switch close state based on symbols:
			else if state == .codeBlock && token.stringValue == "@" {
				endOff = 1; closeChunk = true }
			else if state == .eqBlock   && token.stringValue == "$$"{
				endOff = 2; closeChunk = true }
			else if state == .eqIn   	&& token.stringValue == "$"{
				endOff = 1; closeChunk = true
			}
			// Create a chunk after switching states:
			token = tok.nextToken()!
			if closeChunk {
				if (token.tokenType == eof) { end = fullRange.length }
				else { end = Int(token.offset) }
				if end > fullRange.length { end = fullRange.length }
				if beginInner == 0 { beginInner = begin+beginOff }
				endInner = end-endOff
				if endInner-beginInner > 0 { // has to have at least 3 chars, including ends
					let range = NSMakeRange(begin, end-begin)
					let innerRange = NSMakeRange(beginInner, endInner-beginInner)
					ch = DocumentChunk(chunkType: currType.0, docType: currType.1,
									   equationType: currType.2, range: range,
									   innerRange: innerRange, chunkNumber: chunkIndex)
					chunks.append(ch); chunkIndex += 1
					begin = end
				}
				currType = (.docs, .latex, .none)
				beginOff = 0; endOff = 0; beginInner = 0
				closeChunk = false; state = .sea
			}
		}
		// Handle end cases:
		end = fullRange.length
		if end > begin {
			let range = NSMakeRange(begin, end-begin)
			ch = DocumentChunk(chunkType: currType.0, docType: currType.1,
							   equationType: currType.2, range: range,
							   innerRange: range, chunkNumber: chunkIndex)
			chunks.append(ch); chunkIndex += 1
		}
	}
}

