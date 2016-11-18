//
//  RnwSyntaxParser
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import ClientCore
import Networking
#if os(OSX)
	import AppKit
fileprivate func < <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l < r
  case (nil, _?):
    return true
  default:
    return false
  }
}

fileprivate func > <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l > r
  default:
    return rhs < lhs
  }
}

#endif

open class RnwSyntaxParser: SyntaxParser {
	fileprivate let startExpression:NSRegularExpression
	
	override init(storage: NSTextStorage, fileType: FileType, colorMap: SyntaxColorMap)
	{
		startExpression = try! NSRegularExpression(pattern: "(?:@( \\s*|\\n))|(?:<<([^>]*)>>= ?.*?)", options: [.anchorsMatchLines])
		super.init(storage: storage, fileType: fileType, colorMap: colorMap)
		codeHighlighter = RCodeHighlighter()
		docHighlighter = LatexCodeHighlighter()
		colorBackgrounds = true
	}
	
	override func parseRange(_ fullRange: NSRange) {
		let str = textStorage.string
		let numChunks = startExpression.numberOfMatches(in: str, options: [], range: fullRange)
		guard numChunks > 0 else { return }
		var curChunkNum = 1
		chunks = []
		startExpression.enumerateMatches(in: str, options: [], range: fullRange)
		{ (result, flags, _) -> Void in
			var newChunk:DocumentChunk?
			if curChunkNum == 1 && result!.range.location > 0 { //first chunk
				newChunk = DocumentChunk(chunkType: .documentation, chunkNumber: curChunkNum)
				newChunk?.parsedRange = NSMakeRange(0, result!.range.location)
				self.chunks.append(newChunk!)
				curChunkNum += 1
			}
			let matchStr:String = str.substring(with: result!.range.toStringRange(str)!)
			if matchStr[matchStr.startIndex] == "@" {
				newChunk = DocumentChunk(chunkType: .documentation, chunkNumber: curChunkNum)
			} else  {
				var cname:String?
				if result?.rangeAt(2).length > 0 {
					cname = str.substring(with: (result?.rangeAt(2).toStringRange(str))!)
				}
				newChunk = DocumentChunk(chunkType: .rCode, chunkNumber: curChunkNum, name: cname)
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
