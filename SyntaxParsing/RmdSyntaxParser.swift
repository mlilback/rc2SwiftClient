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

private enum ParserState : Int {
	case sea, codeBlock, codeBlockPoss, codeIn, eqBlock, eqIn, eqPoss, frontMatter
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
		tok.symbolState.add("---")		// frontMatter
		tok.symbolState.add("`r")		// codeIn begin, end
		tok.symbolState.add("`")		// codeIn begin, end
		tok.symbolState.add("$$")		// eqBlock begin, end
		tok.symbolState.add("$")		// eqIn begin, end
		tok.symbolState.add("<math")	// eqPossible
		tok.symbolState.add(">")		// eqBlock mathML definite
		tok.symbolState.add("</math>")	// eqBlock mathML end
		let eof = PKToken.eof().tokenType
		var state = ParserState.sea	// sea - docs chunk
		var begin:Int = 0, end:Int = 0
		var beginInner:Int = 0, endInner:Int = 0
		var beginOff:Int = 0, endOff:Int = 0
		var beginRops:Int = 0
		var rOps = ""
		
		var token = tok.nextToken()!
		// Get FrontMatter:
		var beyondFrontMatter = false
		while !beyondFrontMatter && token.tokenType != eof {
			if token.isWhitespace {
				token = tok.nextToken()!
			}
			else if state == .frontMatter  {
				if token.stringValue == "---" {
					token = tok.nextToken()!
					end = Int(token.offset)-3
					if end > fullRange.length { end = fullRange.length }
					if end-begin > 0 {
						let range = NSMakeRange(begin, end-begin)
						frontMatter = textStorage.string.substring(from: range)!
						begin = end+3
					}
					beyondFrontMatter = true
				}
				else {
					token = tok.nextToken()!
				}
			}
			else if token.stringValue == "---" {
				state = .frontMatter
				token = tok.nextToken()!
				begin = Int(token.offset)
			}
			else {
				beyondFrontMatter = true
			}
		}
		// print("\(frontMatter)")
		// Reference:
		//		public enum ChunkType {
		//			case docs, code, equation
		//		public enum EquationType: String {
		//			case invalid, inline, display, mathML = "MathML"
		var currType:(ChunkType, DocType, EquationType) = (.docs, .rmd, .none)
		var newType = currType
		var closeChunk = false
		var ch:DocumentChunk
		// Parse by loop through tokens and changing states:
		state = .sea
		while token.tokenType != eof {
			// Ignore everything but predefined chunk-defining symbols:
			// print(token.stringValue)
			if token.tokenType != .symbol {
				token = tok.nextToken()!
				continue
			}
			// Switch open state based on symbols:
			if state == .sea || state == .eqPoss || state == .codeBlockPoss {
				if token.stringValue == "```{r" {
					beginRops = Int(token.offset) + 6
					state = .codeBlockPoss
					end = Int(token.offset) }
				else if token.stringValue == "}" && state == .codeBlockPoss {
					newType = (.code, .none, .none)
					let len = Int(token.offset)-beginRops
					if  len > 0 && beginRops > 0 {
						let range = NSMakeRange(beginRops, len)
						rOps = textStorage.string.substring(from: range)!
					} else {
						rOps = ""
					}
					beginRops = 0
					beginInner = Int(token.offset) + 1
					closeChunk = true }
				else if token.stringValue == "`r" {
					newType = (.code, .none, .inline)
					state = .codeIn; beginOff = 2; closeChunk = true }
				else if token.stringValue == "$$" {
					newType = (.equation, .none, .display)
					state = .eqBlock; beginOff = 2; closeChunk = true }
				else if token.stringValue == "$" {
					newType = (.equation, .none, .inline)
					state = .eqIn; beginOff = 1; closeChunk = true }
				else if token.stringValue == "<math" {
					state = .eqPoss
					end = Int(token.offset) }
				else if token.stringValue == ">" && state == .eqPoss {
					newType = (.equation, .none, .mathML)
					beginInner = Int(token.offset) + 1
					closeChunk = true
				}
				if closeChunk {
					if state == .codeBlockPoss { state = .codeBlock }
					else if state == .eqPoss { state = .eqBlock }
					else { end = Int(token.offset) }
					if end > fullRange.length { end = fullRange.length }
					if end-begin > 0 {
						let range = NSMakeRange(begin, end-begin)
						ch = DocumentChunk(chunkType: currType.0, docType: currType.1,
										   equationType: currType.2, range: range,
										   innerRange:range, chunkNumber: chunkIndex)
						chunks.append(ch); chunkIndex += 1
						// print("num=\(ch.chunkNumber)\t range=\(ch.parsedRange)\t inner=\(ch.innerRange)\t type=\(ch.chunkType),\(ch.equationType)")
						begin = end
					}
					currType = newType
					closeChunk = false
				}
			}
				// Switch close state based on symbols:
			else if state == .codeIn    && token.stringValue == "`" {
				endOff = 1; closeChunk = true }
			else if state == .codeBlock && token.stringValue == "```"{
				endOff = 3; closeChunk = true }
			else if state == .eqBlock   && token.stringValue == "$$"{
				endOff = 2; closeChunk = true }
			else if state == .eqIn      && token.stringValue == "$"{
				endOff = 1; closeChunk = true }
			else if state == .eqBlock   && token.stringValue == "</math>"{
				endOff = 7; closeChunk = true
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
									   innerRange: innerRange, chunkNumber: chunkIndex,
									   isInline: state == .eqIn || state == .codeIn)
					if currType.0 == .code && rOps.count > 0 {
						// print(rOps)
						ch.rOps = rOps; rOps = "" }
					chunks.append(ch); chunkIndex += 1
					// print("num=\(ch.chunkNumber)\t range=\(ch.parsedRange)\t inner=\(ch.innerRange)\t type=\(ch.chunkType),\(ch.equationType)")
					begin = end
				}
				currType = (.docs, .rmd, .none)
				beginOff = 0; endOff = 0; beginInner = 0
				closeChunk = false; state = .sea
			}
		}
		// Handle end cases:
		end = fullRange.length
		if beginInner == 0 { beginInner = begin-beginOff }
		endInner = end-endOff
		if endInner-beginInner > 0 {
			let range = NSMakeRange(begin, end-begin)
			let innerRange = NSMakeRange(beginInner, end-begin)
			ch = DocumentChunk(chunkType: currType.0, docType: currType.1,
							   equationType: currType.2, range: range,
							   innerRange: innerRange, chunkNumber: chunkIndex)
			if currType.0 == .code && rOps.count > 0 {
				print(rOps)
				ch.rOps = rOps; rOps = "" }
			chunks.append(ch); chunkIndex += 1
			// print("num=\(ch.chunkNumber)\t range=\(ch.parsedRange)\t inner=\(ch.innerRange)\t type=\(ch.chunkType),\(ch.equationType)")
		}
		// print("\(rOps)")
	}
}

