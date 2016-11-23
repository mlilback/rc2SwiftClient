//
//  SyntaxParser
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
#if os(OSX)
	import AppKit
#endif
import os
import ClientCore
import Networking

extension OSLog {
	static let syntax = OSLog(subsystem: AppInfo.bundleIdentifier, category: "parser")
}

/** parses the contents of an NSTextStorage into an array of chunks that can be syntax colored */
open class SyntaxParser: NSObject {
	///returns the approprate syntax parser to use for fileType
	class func parserWithTextStorage(_ storage:NSTextStorage, fileType:FileType) -> SyntaxParser?
	{
		var parser:SyntaxParser?
		var highlighter:CodeHighlighter?
		let cmap = SyntaxColorMap.standardMap
		if fileType.isSweave {
			parser = RnwSyntaxParser(storage: storage, fileType: fileType, colorMap: cmap)
		} else if fileType.fileExtension == "Rmd" {
			parser = RmdSyntaxParser(storage: storage, fileType: fileType, colorMap: cmap)
		} else if fileType.fileExtension == "R" {
			parser = RSyntaxParser(storage: storage, fileType: fileType, colorMap: cmap)
			highlighter = RCodeHighlighter()
		}
		parser?.codeHighlighter = highlighter
		return parser
	}
	
	let textStorage: NSTextStorage
	let fileType:  FileType
	let colorMap:SyntaxColorMap
	internal(set) var chunks:[DocumentChunk] = []
	fileprivate var lastSource:String = ""
	var colorBackgrounds = false

	internal var docHighlighter:CodeHighlighter?
	internal var codeHighlighter:CodeHighlighter?

	/// - parameter storage: A text storage whose changes are tracked to keep chunks up to date
	/// - parameter fileType: used to determine the proper highlighter(s) to use
	/// - parameter colorMap: The map of token types to colors. Defaults to the singleton standardMap.
	init(storage:NSTextStorage, fileType:FileType, colorMap:SyntaxColorMap = SyntaxColorMap.standardMap)
	{
		self.textStorage = storage
		self.fileType = fileType
		self.colorMap = colorMap
		super.init()
	}
	
	///returns the index of the chunk in the specified range
	func indexOfChunkForRange(range inRange: NSRange) -> Int {
		assert(chunks.count > 0)
		return chunks.index(of: chunksForRange(inRange).first!)!
	}
	
	func chunkForRange(_ inRange:NSRange) -> DocumentChunk? {
		var range = inRange
		if range.location == NSNotFound { return nil }
		if range.location == 0 && range.length == 0 {
			if textStorage.length < 1 { return nil; }
			range = NSMakeRange(0, 1)
		}
		if range.location == textStorage.length && range.length == 0 {
			range.location -= 1
		}
		for aChunk in chunks {
			if NSIntersectionRange(range, aChunk.parsedRange).length > 0 {
				return aChunk
			}
		}
		return nil
	}
	
	func chunksForRange(_ range:NSRange) -> [DocumentChunk] {
		//if full range of textstorage, just return all chunks
		if NSEqualRanges(range, NSMakeRange(0, textStorage.length)) {
			return chunks
		}
		if range.length == 0 {
			guard range.length > 0 else { return [chunks[0]] }
			for aChunk in chunks {
				if NSLocationInRange(range.location-1, aChunk.parsedRange) {
					return [aChunk]
				}
			}
		}
		os_log("looking for %{public}@", log: .syntax, type:.debug, NSStringFromRange(range))
		var outArray:[DocumentChunk] = []
		for aChunk in chunks {
			if NSIntersectionRange(aChunk.parsedRange, range).length > 0
//				|| NSLocationInRange(range.location-1, aChunk.parsedRange)
			{
				outArray.append(aChunk)
			}
		}
		assert(outArray.count > 0)
		return outArray
	}
	
	///returns true if the chunks changed
	@discardableResult func parse() -> Bool {
		if textStorage.string != lastSource {
			let oldChunks = chunks
			parseRange(NSMakeRange(0, textStorage.length))
			lastSource = textStorage.string
			if oldChunks == chunks {
				return false
			}
		}
		return true
	}
	
	internal func parseRange(_ range:NSRange) {
		preconditionFailure("subclass must implement")
	}
	
	func syntaxHighlightChunksInRange(_ range:NSRange) {
		colorChunks(chunksForRange(range))
	}

	///should be called when the textstorage contents have changed, ideally by the NSTextStorageDelegate call textStorage:didProcessEditing:range:changeInLength:
	func adjustParseRanges(_ fullRangeLength:Int) {
		guard chunks.count > 0 else { return }
		for (index,chunk) in chunks.enumerated() {
			guard index+1 < chunks.count - 1 else { break }
			let nextChunk = chunks[index+1]
			var rng = chunk.parsedRange
			rng.length = nextChunk.parsedRange.location - chunk.parsedRange.location
			chunk.parsedRange = rng
		}
		//adjust last one
		var finalRange = chunks.last!.parsedRange
		finalRange.length = fullRangeLength - finalRange.location
		chunks.last!.parsedRange = finalRange
	}
	
	func colorChunks(_ chunksToColor:[DocumentChunk]) {
		for chunk in chunksToColor {
			if chunk.type == .rCode {
				if colorBackgrounds, let bgcolor = colorMap[.CodeBackground] {
					textStorage.addAttribute(NSBackgroundColorAttributeName, value: bgcolor, range: chunk.parsedRange)
				}
				codeHighlighter?.highlightText(textStorage, range: chunk.parsedRange)
			} else if chunk.type == .documentation {
				docHighlighter?.highlightText(textStorage, range: chunk.parsedRange)
			} else if chunk.type == .equation, let bgcolor = colorMap[.EquationBackground] {
				if colorBackgrounds {
					textStorage.addAttribute(NSBackgroundColorAttributeName, value: bgcolor, range: chunk.parsedRange)
				}
			}
		}
	}
}

open class RSyntaxParser:SyntaxParser {
	internal override func parseRange(_ range: NSRange) {
		chunks.removeAll()
		let chunk = DocumentChunk(chunkType: .rCode, chunkNumber: 1)
		chunk.parsedRange = NSMakeRange(0, textStorage.string.characters.count)
		chunks.append(chunk)
	}
}
