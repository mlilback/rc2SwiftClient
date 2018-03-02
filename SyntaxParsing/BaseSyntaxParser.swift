//
//  SyntaxParser
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
#if os(OSX)
	import AppKit
#endif
// Required for theme = Property(ThemeManager...):
import ClientCore
import ReactiveSwift
import Model

/// Parent class of specific parsers that must be implemented and base
/// implementation of protocol SyntaxParser used externally.
/// Parses the contents of an NSTextStorage into an array of chunks
/// that can be syntax colored.
public class BaseSyntaxParser: NSObject, SyntaxParser {
	// SyntaxParser protocol (model):
	public let textStorage: NSTextStorage
	public let fileType: FileType
	public internal(set) var chunks: [DocumentChunk] = []
	// Highlighting:
	public let theme = Property(ThemeManager.shared.activeSyntaxTheme)	// move?
	internal var codeHighlighter: BaseHighlighter?
	internal var docHighlighter: BaseHighlighter?
	internal var eqnHighlighter: BaseHighlighter?
	var colorBackgrounds = true
	// Private:
	fileprivate var textStorageStringLast: String = ""

	// See SyntaxParser protocol for parameters.
	init(storage: NSTextStorage, fileType: FileType, helpCallback: @escaping HighlighterHasHelpCallback)
	{
		self.textStorage = storage
		self.fileType = fileType
		super.init()
		codeHighlighter?.helpCallback = helpCallback
	}
	
	// Returns the approprate syntax parser (and highlighter) to use for fileType.
	public class func parserWithTextStorage(_ storage: NSTextStorage, fileType: FileType, helpCallback: @escaping HighlighterHasHelpCallback) -> BaseSyntaxParser?
	{
		var parser: BaseSyntaxParser?
		let codeHighlighter = RCodeHighlighter(helpCallback: helpCallback)
		if fileType.fileExtension == "Rnw" {		// R-sweave
			parser = RnwSyntaxParser(storage: storage, fileType: fileType, helpCallback: helpCallback)
			parser?.docHighlighter = LatexHighlighter(helpCallback: helpCallback)
			parser?.eqnHighlighter = parser?.docHighlighter
		} else if fileType.fileExtension == "Rmd" {	// R-markdown
			parser = RmdSyntaxParser(storage: storage, fileType: fileType, helpCallback: helpCallback)
			parser?.eqnHighlighter = LatexHighlighter(helpCallback: helpCallback)
		} else if fileType.fileExtension == "R" {	// R-only
			parser = RSyntaxParser(storage: storage, fileType: fileType, helpCallback: helpCallback)
			parser?.colorBackgrounds = false
		}
		parser?.codeHighlighter = codeHighlighter
		return parser
	}
	
	// Called by parse (called externally), which in turn calls parseRange
	// implemented by particular parser subclasses.
	internal func parseRange(_ range: NSRange) {
		preconditionFailure("subclass must implement")
	}

	// MARK: - External use only (mainly SessionEditorController)
	// See SyntaxParser protocol for documentation of each of the following.
	public var executableChunks: [DocumentChunk] {
		return chunks.filter({ $0.chunkType == .code }) }
	
	@discardableResult
	public func parse() -> Bool {
		// Only parse if text has changed since last:
		if textStorage.length == 0 || textStorage.string != textStorageStringLast {
			let chunksLast = chunks
			parseRange(NSRange(location: 0, length: textStorage.length))
			textStorageStringLast = textStorage.string
			// return true if the chunks array was updated:
			if chunksLast == chunks {
				return false
			}
		}
		return true
	}
	
	public func indexOfChunk(inRange: NSRange) -> Int {
		guard chunks.count > 0,
			let firstChunkInRange = chunksForRange(inRange).first,
			let chunkIndex = chunks.index(of: firstChunkInRange)
			else { return 0 }
		return chunkIndex
	}
	
	// Called by indexOfChunk.
	public func chunksForRange(_ range: NSRange) -> [DocumentChunk] {
		// If no chunks, return []:
		guard chunks.count > 0 else { return [] }
		// If range == full range of textstorage, just return all chunks:
		if NSEqualRanges(range, NSRange(location: 0, length: textStorage.length)) {
			return chunks
		}
		// If only a single location, return the chunk it's in (in []).
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
			if NSIntersectionRange(aChunk.parsedRange, range).length > 0
			//				|| NSLocationInRange(range.location-1, aChunk.parsedRange)
			{
				outArray.append(aChunk)
			}
		}
		return outArray
	}
	
	public func colorChunks(_ chunksToColor: [DocumentChunk]) {
		for chunk in chunksToColor {
			var bgcolor = theme.value.color(for: .background)
			if chunk.chunkType == .code {
				bgcolor = theme.value.color(for: .codeBackground)
				codeHighlighter?.highlightText(textStorage, range: chunk.parsedRange)
			} else if chunk.chunkType == .docs {
				bgcolor = theme.value.color(for: .background)
				docHighlighter?.highlightText(textStorage, range: chunk.parsedRange)
			} else if chunk.chunkType == .equation {
				bgcolor = theme.value.color(for: .equationBackground)
				if chunk.equationType != .mathML {
					eqnHighlighter?.highlightText(textStorage, range: chunk.parsedRange)
				}
			}
			if colorBackgrounds {
				textStorage.addAttribute(.backgroundColor, value: bgcolor, range: chunk.parsedRange)
			}
		}
	}
}

// If the text is only just R, then there is only one chunk of the entire
// text and no chunk parsing required.
class RSyntaxParser: BaseSyntaxParser {
	internal override func parseRange(_ range: NSRange) {
		chunks.removeAll()
		let range = NSRange(location: 0, length: textStorage.string.count) // whole txt
		let chunk = DocumentChunk(chunkType: .code, equationType: .none,
								  range: range, chunkNumber: 1)
		chunks.append(chunk)
	}
}

