//
//  SyntaxParser
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
#if os(OSX)
	import AppKit
#endif
import Model	// required for FileType
import PEGKit
import MJLLogger

/// Multi-language syntax parser that takes an NSTextStorage object, switches
/// parsing modes based on FileType, creates DocumentChunk's, and applies
/// custom attributes (DocType, ChunkType, FragmentType, EquationType),
/// for later highlighting text of a NSMutableAttributedString by Highlighter,
/// for the purpose of highlighting: code, equation, quotes, comments, etc.
/// This also creates help links to R keywords.
public class SyntaxParser: NSObject {
	// SyntaxParser protocol (model):
	public let textStorage: NSTextStorage
	public var docType: DocType = .r
	public var keywords: Set<String>
	public var frontMatter = ""
	public internal(set) var chunks: [DocumentChunk] = []
	public var helpCallback: HasHelpCallback?
	// Private:
	private var textStorageStringLast: String = ""
	private enum ParserState : Int {
		case sea, codeBlock, codeBlockPoss, codeIn, eqBlock, eqIn, eqPoss, frontMatter
	}
	
	public init(storage: NSTextStorage, fileType: FileType, helpCallback: @escaping HasHelpCallback)
	{
		self.textStorage = storage
		self.keywords = SyntaxParser.rKeywords
		self.helpCallback = helpCallback
		if fileType.fileExtension == "Rnw" {		// R-sweave (latex with R)
			self.docType = .latex
		} else if fileType.fileExtension == "Rmd" {	// R-markdown
			self.docType = .rmd
		} else if fileType.fileExtension == "R" {	// R-only
			self.docType = .r
		}
		super.init()
	}
	
	// Get RKeywords from a file in it's bundle:
	static let rKeywords: Set<String> = {
		let bundle = Bundle(for: SyntaxParser.self)
		guard let url = bundle.url(forResource: "RKeywords", withExtension: "txt")
			else { fatalError("failed to find RKeywords file")
		}
		// swiftlint:disable:next force_try
		let encoding = String.Encoding.utf8.rawValue
		let keyArray = try! NSString(contentsOf: url, encoding: encoding).components(separatedBy: "\n")
		return Set<String>(keyArray)
	}()
	
	// MARK: - Chunk funcs:
	public var executableChunks: [DocumentChunk] {
		return chunks.filter({ $0.chunkType == .code })
	}
	
	public func indexOfChunk(inRange: NSRange) -> Int {
		guard chunks.count > 0,
			let firstChunkInRange = chunksForRange(inRange).first,
			let chunkIndex = chunks.index(of: firstChunkInRange)
			else { return 0 }
		return chunkIndex
	}
	
	// Called by indexOfChunk:
	public func chunksForRange(_ range: NSRange) -> [DocumentChunk] {
		// If no chunks, return []:
		guard chunks.count > 0 else { return [] }
		// If range == full range of textstorage, just return all chunks:
		if NSEqualRanges(range, NSRange(location: 0, length: textStorage.length)) {
			return chunks
		}
		// If only a single location, return the chunk it's in range:
		if range.length == 0 {
			guard range.location > 0 else { return [chunks[0]] }
			for aChunk in chunks {
				if NSLocationInRange(range.location, aChunk.parsedRange) {
					return [aChunk]
				}
			}
		}
		// Return potentially more than one chunk:
		var outArray: [DocumentChunk] = []
		for aChunk in chunks {
			if NSIntersectionRange(aChunk.parsedRange, range).length > 0 {
				outArray.append(aChunk)
			}
		}
		return outArray
	}
	
	// MARK: - Parser funcs:
	@discardableResult
	public func parse() -> Bool {
		// Only parse if text has changed since last:
		if textStorage.length > 0 && textStorage.string != textStorageStringLast {
			let chunksLast = chunks
			let fullRange = NSRange(location: 0, length: textStorage.length)
			parseAndAttribute(attributedString: textStorage,
							  docType: docType, inRange: fullRange, makeChunks: true)
			textStorageStringLast = textStorage.string
			// return true if the chunks array was updated:
			if chunksLast != chunks {
				return true
			}
		}
		return false
	}
	
	public func parseAndAttribute(attributedString: NSMutableAttributedString,
								  docType: DocType, inRange: NSRange, makeChunks: Bool) {
		if makeChunks {
			// Clear and reinit chunks:
			chunks.removeAll(); chunks = [DocumentChunk]();
		}
		var chunkIndex = 1
		// Remove previous attributes:
		let aStr = attributedString
		aStr.removeAttribute(DocTypeKey, range:inRange)
		aStr.removeAttribute(ChunkTypeKey, range:inRange)
		aStr.removeAttribute(FragmentTypeKey, range:inRange)
		aStr.removeAttribute(EquationTypeKey, range:inRange)
		// Set up PEG Kit tokenizer:
		let tok = PKTokenizer(string: attributedString.string)!
		setBaseTokenizer(tok)
		// Default (rmd) chunk begin & end symbols:
		//>>>TODO: make blocks only work at beginning, skip \n#...
		var codeBlockPoss = "```{r", codeBlockBegin = "}", codeBlockEnd = "```\n"
		let codeInlineBegin	= "`r", codeInlineEnd = "`"
		let eqBlock = "$$", eqInline = "$"
		// For R-Markdown,
		if docType == .rmd {
			// add markdown comment tokens:
			tok.setTokenizerState(tok.commentState, from:hashChar, to:hashChar)
			tok.commentState.addSingleLineStartMarker("##") // yes, correct
			// add HTML comment tokens:
			tok.setTokenizerState(tok.commentState, from:lessChar, to:lessChar)
			tok.commentState.addMultiLineStartMarker("<!--", endMarker:"-->")
		}
		// For LaTex,
		if docType == .latex {
			// add LaTex comment tokens:
			tok.setTokenizerState(tok.commentState, from:percentChar, to:percentChar)
			tok.commentState.addSingleLineStartMarker("%")
			tok.setTokenizerState(tok.commentState, from:backSlashChar, to:backSlashChar)
			tok.commentState.addMultiLineStartMarker("\\begin{comment}", endMarker:"\\end{comment}")
			tok.commentState.addMultiLineStartMarker("\\iffalse", endMarker:"\\fi")
			// Change chunk begin & end symbols:
			codeBlockPoss = "<<"; codeBlockBegin = ">>="; codeBlockEnd = "@"
//?			tok.symbolState.remove("\"")
//?			tok.symbolState.remove("\'")
		}
		// Add recognition of block symbol tokens:
		tok.symbolState.add(codeBlockPoss); tok.symbolState.add(codeBlockBegin)
		tok.symbolState.add(codeBlockEnd)
		tok.symbolState.add(codeInlineBegin); tok.symbolState.add(codeInlineEnd)
		tok.symbolState.add(eqBlock); tok.symbolState.add(eqInline)
		tok.symbolState.add("<math")	// eqBlock mathML possible
		tok.symbolState.add(">")		// eqBlock mathML definite
		tok.symbolState.add("</math>")	// eqBlock mathML end
		let frontMatterSymbol = "---\n"
		tok.symbolState.add(frontMatterSymbol)
		// Init Range parameters:
		var begin:Int = 0, end:Int = 0
		var beginInner:Int = 0, endInner:Int = 0
		var beginOff:Int = 0, endOff:Int = 0
		var beginRops:Int = 0
		var rOps = ""
		// Get first token and add recognition for end token:
		let eof = PKToken.eof().tokenType	// End of File (or string)
		var token = tok.nextToken()!
		// Parsing will largely be done by switching between ParserState's:
		var state = ParserState.sea	// sea - docs chunk
		
		// Get FrontMatter:
		var beyondFrontMatter = false
		if docType == .r { beyondFrontMatter = true }
		while !beyondFrontMatter && token.tokenType != eof {
			if token.isWhitespace {
				token = tok.nextToken()!
			}
			else if state == .frontMatter  {
				if token.stringValue == frontMatterSymbol {
					token = tok.nextToken()!
					end = Int(token.offset) - frontMatterSymbol.count
					if end > inRange.length { end = inRange.length }
					if end-begin > 0 {
						let range = NSMakeRange(begin, end-begin)
						frontMatter = textStorage.string.substring(from: range)!
						begin = end + frontMatterSymbol.count
					}
					beyondFrontMatter = true
				}
				else {
					token = tok.nextToken()!
				}
			}
			else if token.stringValue == frontMatterSymbol {
				state = .frontMatter
				token = tok.nextToken()!
				begin = Int(token.offset)
			}
			else {
				beyondFrontMatter = true
			}
		}
		
		// Initial states:
		var currChunkType:ChunkType = .docs
		var newChunkType = currChunkType
		var currEquationType:EquationType = .none
		var newEquationType = currEquationType
		state = .sea
		var closeChunk = false
		var lastToken: PKToken?
		// Parse by loop through tokens and changing states:
		while token.tokenType != eof {
			// print(token.stringValue)
			// Add attributes for Quotes, Comments, Numbers, Symbols, and Keywords:
			var range = NSMakeRange(Int(token.offset), token.stringValue.count)
			var frag = FragmentType.none
			if token.isQuotedString || token.stringValue == "\"" {
				frag = .quote
				aStr.addAttribute(FragmentTypeKey, value:frag, range:range)
			}
			else if token.tokenType == .comment { frag = .comment }
			else if token.tokenType == .quotedString { frag = .quote }
			else if token.tokenType == .number { frag = .number }
			// else if token.tokenType == .symbol { frag = .symbol }
			else if token.tokenType == .word {
				if newChunkType == .code && keywords.contains(token.stringValue) {
					frag = .keyword
					if helpCallback?(token.stringValue) ?? false {
						aStr.addAttribute(.link, value: "help:\(token.stringValue!)",
							range: range)
					}
				}
				else if docType == .latex || newChunkType == .equation {
					if lastToken?.tokenType == .symbol &&
						lastToken?.stringValue.first == "\\" {
						range.location -= 1; range.length += 1
						frag = .keyword
					}
				}
			}
			if frag != .none {
				aStr.addAttribute(FragmentTypeKey, value:frag, range:range)
			}
			
			if token.tokenType != .symbol || docType == .r {
				//>>> make .r chunk?
				lastToken = token
				token = tok.nextToken()!
				continue
			}
			// Switch open state based on symbols:
			if state == .sea || state == .eqPoss || state == .codeBlockPoss {
				if token.stringValue == codeBlockPoss {
					state = .codeBlockPoss
					end = Int(token.offset) }
				else if token.stringValue == codeBlockBegin && state == .codeBlockPoss {
					newChunkType = .code; newEquationType = .display
					let len = Int(token.offset)-beginRops
					if  len > 0 && beginRops > 0 {
						let range = NSMakeRange(beginRops, len)
						rOps = aStr.string.substring(from: range)!
					} else {
						rOps = ""
					}
					beginRops = 0
					beginInner = Int(token.offset) + codeBlockBegin.count
					closeChunk = true }
				else if token.stringValue == codeInlineBegin {
					newChunkType = .code; newEquationType = .inline
					state = .codeIn; beginOff = codeInlineBegin.count; closeChunk = true }
				else if token.stringValue == eqBlock {
					newChunkType = .equation; newEquationType = .display
					state = .eqBlock; beginOff = eqBlock.count; closeChunk = true }
				else if token.stringValue == eqInline {
					newChunkType = .equation; newEquationType = .inline
					state = .eqIn; beginOff = eqInline.count; closeChunk = true }
				else if token.stringValue == "<math" {
					state = .eqPoss
					end = Int(token.offset) }
				else if token.stringValue == ">" && state == .eqPoss {
					newChunkType = .equation; newEquationType = .mathML
					beginInner = Int(token.offset) + ">".count
					closeChunk = true
				}
				if closeChunk {
					if state == .codeBlockPoss { state = .codeBlock }
					else if state == .eqPoss { state = .eqBlock }
					else { end = Int(token.offset) }
					if end > inRange.length { end = inRange.length }
					if end-begin > 0 {
						let range = NSMakeRange(begin, end-begin)
						if makeChunks {
							let ch = DocumentChunk(chunkType:currChunkType,
												   docType:docType,
												   equationType:currEquationType,
												   range:range, innerRange:range,
												   chunkNumber:chunkIndex)
							chunks.append(ch); chunkIndex += 1
							Log.debug("num=\(ch.chunkNumber)\t range=\(ch.parsedRange)\t inner=\(ch.innerRange)\t type=\(ch.chunkType),\(ch.equationType)", .parser)
						}
						aStr.addAttribute(ChunkTypeKey, value:currChunkType, range:range)
						begin = end
					}
					currChunkType = newChunkType; currEquationType = newEquationType
					closeChunk = false
				}
			}
			// Switch close state based on symbols:
			else if state == .codeBlock && token.stringValue == codeBlockEnd {
				endOff = codeBlockEnd.count; closeChunk = true }
			else if state == .codeIn    && token.stringValue == codeInlineEnd {
				endOff = codeInlineEnd.count; closeChunk = true }
			else if state == .eqBlock   && token.stringValue == eqBlock {
				endOff = eqBlock.count; closeChunk = true }
			else if state == .eqIn      && token.stringValue == eqInline {
				endOff = eqInline.count; closeChunk = true }
			else if state == .eqBlock   && token.stringValue == "</math>"{
				endOff = "</math>".count; closeChunk = true
			}
			// Create a chunk after switching states:
			lastToken = token
			token = tok.nextToken()!
			if closeChunk {
				if (token.tokenType == eof) { end = inRange.length }
				else { end = Int(token.offset) }
				if end > inRange.length { end = inRange.length }
				if beginInner == 0 { beginInner = begin+beginOff }
				endInner = end-endOff
				if endInner-beginInner > 0 { // has to have at least 3 chars, including ends
					let range = NSMakeRange(begin, end-begin)
					let innerRange = NSMakeRange(beginInner, endInner-beginInner)
					aStr.addAttribute(ChunkTypeKey, value:currChunkType, range:range)
					aStr.addAttribute(EquationTypeKey, value:currEquationType, range:range)
					let ch = DocumentChunk(chunkType:currChunkType,
										   docType:docType,
										   equationType:currEquationType,
										   range:range, innerRange:innerRange,
										   chunkNumber:chunkIndex,
										   isInline: (state == .eqIn || state == .codeIn))
					if newChunkType == .code && rOps.count > 0 { ch.rOps = rOps; rOps = "" }
					chunks.append(ch); chunkIndex += 1
					Log.debug("num=\(ch.chunkNumber)\t range=\(ch.parsedRange)\t inner=\(ch.innerRange)\t type=\(ch.chunkType),\(ch.equationType)", .parser)
					begin = end
				}
				currChunkType = .docs; currEquationType = .none
				beginOff = 0; endOff = 0; beginInner = 0
				closeChunk = false; state = .sea
			}
		}
		// Handle end cases:
		end = inRange.length
		if beginInner == 0 { beginInner = begin-beginOff }
		endInner = end-endOff
		if endInner-beginInner > 0 {
			let range = NSMakeRange(begin, end-begin)
			let innerRange = NSMakeRange(beginInner, end-begin)
			aStr.addAttribute(ChunkTypeKey, value:currChunkType, range:range)
			aStr.addAttribute(EquationTypeKey, value:currEquationType, range:range)
			let ch = DocumentChunk(chunkType:currChunkType,
								   docType:docType,
								   equationType:currEquationType,
								   range:range, innerRange:innerRange,
								   chunkNumber:chunkIndex,
								   isInline: (state == .eqIn || state == .codeIn))
			if newChunkType == .code && rOps.count > 0 { ch.rOps = rOps; rOps = "" }
			chunks.append(ch); chunkIndex += 1
			Log.debug("num=\(ch.chunkNumber)\t range=\(ch.parsedRange)\t inner=\(ch.innerRange)\t type=\(ch.chunkType),\(ch.equationType)", .parser)
		}
	}
}
