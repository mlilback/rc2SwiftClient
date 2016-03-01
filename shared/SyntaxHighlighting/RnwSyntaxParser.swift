//
//  RnwSyntaxParser
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
#if os(OSX)
	import AppKit
#endif

class RnwSyntaxParser: SyntaxParser {
	private let startExpression:NSRegularExpression
	
	override init(storage: NSTextStorage, fileType: FileType, colorMap: SyntaxColorMap)
	{
		startExpression = try! NSRegularExpression(pattern: "(?:@( \\s*|\\n))|(?:<<([^>]*)>>= ?.*?)", options: [.AnchorsMatchLines])
		super.init(storage: storage, fileType: fileType, colorMap: colorMap)
		codeHighlighter = RCodeHighlighter()
		docHighlighter = LatexCodeHighlighter()
	}
	
	override func parseRange(fullRange: NSRange) {
		let str = textStorage.string
		let numChunks = startExpression.numberOfMatchesInString(str, options: [], range: fullRange)
		guard numChunks > 0 else { return }
		var curChunkNum = 1
		chunks = []
		startExpression.enumerateMatchesInString(str, options: [], range: fullRange)
		{ (result, flags, _) -> Void in
			var newChunk:DocumentChunk?
			if curChunkNum == 1 && result!.range.location > 0 { //first chunk
				newChunk = DocumentChunk(chunkType: .Documentation, chunkNumber: curChunkNum)
				newChunk?.parsedRange = NSMakeRange(0, result!.range.location)
				self.chunks.append(newChunk!)
				curChunkNum += 1
			}
			let matchStr:String = str.substringWithRange(result!.range.toStringRange(str)!)
			if matchStr[matchStr.startIndex] == "@" {
				newChunk = DocumentChunk(chunkType: .Documentation, chunkNumber: curChunkNum)
			} else  {
				var cname:String?
				if result?.rangeAtIndex(2).length > 0 {
					cname = str.substringWithRange((result?.rangeAtIndex(2).toStringRange(str))!)
				}
				newChunk = DocumentChunk(chunkType: .RCode, chunkNumber: curChunkNum, name: cname)
			}
			if let chunkToAdd = newChunk {
				chunkToAdd.parsedRange = result!.range
				chunkToAdd.contentOffset = result!.range.length + 1
				self.chunks.append(chunkToAdd)
				curChunkNum += 1
			}
		}
		adjustParseRanges(fullRange.length)
		colorChunks(chunks)
	}
}
