//
//  SyntaxParser
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
#if os(OSX)
	import AppKit
#endif

let ChunkStartAttribute = "ChunkStartAttribute"

class SyntaxParser: NSObject {
	///returns the approprate syntax parser to use for fileType
	class func parserWithTextStorage(storage:NSTextStorage, fileType:FileType) -> SyntaxParser?
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
	var chunks:[DocumentChunk] = []
	private var lastSource:String = ""

	var docHighlighter:CodeHighlighter?
	var codeHighlighter:CodeHighlighter?

	init(storage:NSTextStorage, fileType:FileType, colorMap:SyntaxColorMap = SyntaxColorMap.standardMap)
	{
		self.textStorage = storage
		self.fileType = fileType
		self.colorMap = colorMap
		super.init()
	}
	
	func chunkForRange(var range:NSRange) -> DocumentChunk? {
		if range.location == NSNotFound { return nil }
		if range.location == 0 && range.length == 0 {
			if textStorage.length < 1 { return nil; }
			range = NSMakeRange(0, 1)
		}
		if range.location == textStorage.length && range.length == 0 {
			range.location -= 1
		}
		return textStorage.attribute(ChunkStartAttribute, atIndex: range.location, effectiveRange: nil) as? DocumentChunk
	}
	
	func chunksForRange(range:NSRange) -> [DocumentChunk] {
		var outArray:[DocumentChunk] = []
		textStorage.enumerateAttribute(ChunkStartAttribute, inRange: range, options: [])
		{ (value, rng, _) -> Void in
			outArray.append(value as! DocumentChunk)
		}
		return outArray
	}
	
	func parse() {
		if textStorage.string != lastSource {
			parseRange(NSMakeRange(0, textStorage.length))
			lastSource = textStorage.string
		}
	}
	
	func parseRange(range:NSRange) {
		preconditionFailure("subclass must implement")
	}
	
	func syntaxHighlightChunksInRange(range:NSRange) {
		colorChunks(chunksForRange(range))
	}

	func adjustParseRanges(fullRangeLength:Int) {
		guard chunks.count > 0 else { return }
		for (index,chunk) in chunks.enumerate() {
			guard index+1 < chunks.count - 1 else { break }
			let nextChunk = chunks[index+1]
			var rng = chunk.parseRange
			rng.length = nextChunk.parseRange.location - chunk.parseRange.location
			chunk.parseRange = rng
		}
		//adjust last one
		var finalRange = chunks.last!.parseRange
		finalRange.length = fullRangeLength - finalRange.location
		chunks.last!.parseRange = finalRange
	}
	
	func colorChunks(chunksToColor:[DocumentChunk]) {
		for chunk in chunksToColor {
			textStorage.addAttribute(ChunkStartAttribute, value: chunk, range: chunk.parseRange)
			if chunk.type == .RCode {
				if let bgcolor = colorMap[.CodeBackground] {
					textStorage.addAttribute(NSBackgroundColorAttributeName, value: bgcolor, range: chunk.parseRange)
				}
				codeHighlighter?.highlightText(textStorage, range: chunk.parseRange)
			} else if chunk.type == .Documentation {
				docHighlighter?.highlightText(textStorage, range: chunk.parseRange)
			}
		}
	}
}

class RSyntaxParser:SyntaxParser {
	override func parseRange(range: NSRange) {
		codeHighlighter?.highlightText(textStorage, range: range)
	}
}
