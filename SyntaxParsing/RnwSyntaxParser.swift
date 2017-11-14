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
#endif
import Model

class RnwSyntaxParser: BaseSyntaxParser {
	fileprivate let startExpression: NSRegularExpression
	
	override init(storage: NSTextStorage, fileType: FileType, helpCallback: @escaping HighlighterHasHelpCallback)
	{
		// swiftlint:disable:next force_try
		startExpression = try! NSRegularExpression(pattern: "(?:@( \\s*|\\n))|(?:<<([^>]*)>>= ?.*?)", options: [.anchorsMatchLines])
		super.init(storage: storage, fileType: fileType, helpCallback: helpCallback)
		codeHighlighter = RCodeHighlighter(helpCallback: helpCallback)
		docHighlighter = LatexCodeHighlighter(helpCallback: helpCallback)
		colorBackgrounds = true
	}
	
	override func parseRange(_ fullRange: NSRange) {
		let str = textStorage.string
		let numChunks = startExpression.numberOfMatches(in: str, options: [], range: fullRange)
		guard numChunks > 0 else { return }
		var curChunkNum = 1
		chunks = []
		startExpression.enumerateMatches(in: str, options: [], range: fullRange)
		{ (result, _, _) -> Void in
			guard let result = result else { return }
			var newChunk: DocumentChunk?
			if curChunkNum == 1 && result.range.location > 0 { //first chunk
				newChunk = DocumentChunk(chunkType: .documentation, chunkNumber: curChunkNum)
				newChunk?.parsedRange = NSRange(location: 0, length: result.range.location)
				self.chunks.append(newChunk!)
				curChunkNum += 1
			}
			let matchStr = String(str[result.range.toStringRange(str)!])
			if matchStr[matchStr.startIndex] == "@" {
				newChunk = DocumentChunk(chunkType: .documentation, chunkNumber: curChunkNum)
			} else  {
				var cname: String?
				if let subRange = result.range(at: 2).toStringRange(str) {
					cname = String(str[subRange])
				}
				newChunk = DocumentChunk(chunkType: .executable, chunkNumber: curChunkNum, name: cname)
			}
			if let chunkToAdd = newChunk {
				chunkToAdd.parsedRange = result.range
//				chunkToAdd.contentOffset = result.range.length + 1
				self.chunks.append(chunkToAdd)
				curChunkNum += 1
			}
		}
		adjustParseRanges(fullRange.length)
		colorChunks(chunks)
	}
}
