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
	
	override func parseRange(_ fullRange: NSRange) {
		// Clear and reinit chunks:
		chunks.removeAll();
		chunks = [DocumentChunk](); var chunkIndex = 1
		// PEG Kit:
		let tok = PKTokenizer(string: textStorage.string)!
		setBaseTokenizer(tok)
		tok.setTokenizerState(tok.commentState, from:hashChar, to:hashChar)
		tok.commentState.addSingleLineStartMarker("#")
		tok.setTokenizerState(tok.commentState, from:lessChar, to:lessChar)
		tok.commentState.addMultiLineStartMarker("<!--", endMarker:"-->")
		// Order of ``` before ` matters:
		tok.symbolState.add("```{r")	// codeBlock begin, end
		tok.symbolState.add("```")		// codeBlock end
		tok.symbolState.add("`r")		// codeIn begin, end
		tok.symbolState.add("`")		// codeIn begin, end
		tok.symbolState.add("$$")		// eqBlock begin, end
		tok.symbolState.add("$")		// eqIn begin, end
		tok.symbolState.add("<math")	// eqPossible
		tok.symbolState.add(">")		// eqBlock mathML definite
		tok.symbolState.add("</math>")	// eqBlock mathML end
		let eof = PKToken.eof().tokenType
		var state = RmdParserState.sea	// sea - docs chunk
		var begin:Int = 0, end:Int = 0
		var token = tok.nextToken()!
		var closeChunk = false
		// Reference:
		//		public enum ChunkType {
		//			case docs, code, equation
		//		public enum EquationType: String {
		//			case invalid, inline, display, mathML = "MathML"
		var currType:(ChunkType, DocType, EquationType) = (.docs, .rmd, .none)
		var newType = currType
		var ch:DocumentChunk
		// Parse by loop through tokens and changing states:
		while token.tokenType != eof {
			// Ignore everything but predefined chunk-defining symbols:
			//			print(token.stringValue)
			if token.tokenType != .symbol {
				token = tok.nextToken()!
				continue
			}
			// Switch open state based on symbols:
			if state == .sea || state == .eqPossible {
				if token.stringValue == "```{r" {
					newType = (.code, .none, .none); state = .codeBlock
					closeChunk = true }
				else if token.stringValue == "`r" {
					newType = (.code, .none, .none); state = .codeIn
					closeChunk = true }
				else if token.stringValue == "$$" {
					newType = (.equation, .none, .display); state = .eqBlock
					closeChunk = true }
				else if token.stringValue == "$" {
					newType = (.equation, .none, .inline); state = .eqIn
					closeChunk = true }
				else if token.stringValue == "<math" {
					state = .eqPossible
					end = Int(token.offset) }
				else if token.stringValue == ">" && state == .eqPossible {
					newType = (.equation, .none, .mathML)
					closeChunk = true
				}
				if closeChunk {
					if state == .eqPossible { state = .eqBlock }
					else { end = Int(token.offset) }
					if end > fullRange.length { end = fullRange.length }
					if end-begin > 0 {
						let range = NSMakeRange(begin, end-begin)
						ch = DocumentChunk(chunkType: currType.0, docType: currType.1,
										   equationType: currType.2, range: range,
										   chunkNumber: chunkIndex)
						chunks.append(ch); chunkIndex += 1
						//						print("num=\(ch.chunkNumber)\t range=\(ch.parsedRange)\t type=\(ch.chunkType),\(ch.equationType)")
					}
					currType = newType; begin = end
					closeChunk = false
				}
			}
				// Switch close state based on symbols:
			else if state == .codeIn    && token.stringValue == "`" {
				closeChunk = true }
			else if state == .codeBlock && token.stringValue == "```"{
				closeChunk = true }
			else if state == .eqBlock   && token.stringValue == "$$"{
				closeChunk = true }
			else if state == .eqIn      && token.stringValue == "$"{
				closeChunk = true }
			else if state == .eqBlock   && token.stringValue == "</math>"{
				closeChunk = true
			}
			// Create a chunk after switching states:
			token = tok.nextToken()!
			if closeChunk {
				if (token.tokenType == eof) { end = fullRange.length }
				else { end = Int(token.offset) }
				if end > fullRange.length { end = fullRange.length }
				if end-begin > 2 { // has to have at least 3 chars, including ends
					let range = NSMakeRange(begin, end-begin)
					ch = DocumentChunk(chunkType: currType.0, docType: currType.1,
									   equationType: currType.2, range: range,
									   chunkNumber: chunkIndex, isInline: state == .eqIn || state == .codeIn)
					chunks.append(ch); chunkIndex += 1
					//					print("num=\(ch.chunkNumber)\t range=\(ch.parsedRange)\t type=\(ch.chunkType),\(ch.equationType)")
					begin = end
				}
				currType = (.docs, .rmd, .none)
				closeChunk = false; state = .sea
			}
		}
		// Handle end cases:
		end = fullRange.length
		if end > begin {
			let range = NSMakeRange(begin, end-begin)
			ch = DocumentChunk(chunkType: currType.0, docType: currType.1,
							   equationType: currType.2, range: range,
							   chunkNumber: chunkIndex)
			chunks.append(ch); chunkIndex += 1
		}
	}
}

