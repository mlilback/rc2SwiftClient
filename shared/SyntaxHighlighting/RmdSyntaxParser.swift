//
//  RmdSyntaxParser
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
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

open class RmdSyntaxParser: SyntaxParser {
	let latexHighlighter:LatexCodeHighlighter = LatexCodeHighlighter()
	let rChunkRegex:NSRegularExpression
	let blockEqRegex: NSRegularExpression
	let inlineRegex:NSRegularExpression
	let mathRegex:NSRegularExpression
	
	override init(storage: NSTextStorage, fileType: FileType, colorMap: SyntaxColorMap)
	{
		try! rChunkRegex = NSRegularExpression(pattern: "\n```\\{r\\s*([^\\}]*)\\}\\s*\n+(.*?)\n```\n", options: .dotMatchesLineSeparators)
		//matches: $$
		try! blockEqRegex = NSRegularExpression(pattern: "(\\$\\$\\p{blank}*\\n+(.*?)\\$\\$\\p{blank}*\n)", options:.dotMatchesLineSeparators)
		try! inlineRegex = NSRegularExpression(pattern: "`r\\s+([^`]*)`", options: .dotMatchesLineSeparators)
		try! mathRegex = NSRegularExpression(pattern: "(<math(\\s+[^>]*)(display\\s*=\\s*\"(block|inline)\")([^>]*)>)(.*?)</math>\\s*?\\n?", options: .dotMatchesLineSeparators)
		
		super.init(storage: storage, fileType: fileType, colorMap: colorMap)
		codeHighlighter = RCodeHighlighter()
		colorBackgrounds = true
	}
	
	override func parseRange(_ range: NSRange) {
		let str = textStorage.string
		chunks.removeAll()
		var nextChunkIndex = 1
		var newChunks = [DocumentChunk]()
		var inlineMathML = [NSRange]()
		//add R code chunks
		rChunkRegex.enumerateMatches(in: str, options: [], range: range)
		{ (result, flags, _) -> Void in
			var cname:String?
			if result?.rangeAt(1).length > 0 {
				cname = str.substring(with: result!.rangeAt(1).toStringRange(str)!)
			}
			let codeChunk = DocumentChunk(chunkType: .rCode, chunkNumber: nextChunkIndex, name: cname)
			nextChunkIndex += 1
			let mrng = result!.range //rangeAtIndex(0)
			//skip the initial newline
			codeChunk.parsedRange = NSMakeRange(mrng.location + 1, mrng.length - 1)
			newChunks.append(codeChunk)
		}
		//add chunks for block equations
		blockEqRegex.enumerateMatches(in: str, options: [], range: range)
		{ (results, _, _) -> Void in
			let newChunk = DocumentChunk(chunkType: .equation, chunkNumber: nextChunkIndex)
			newChunk.equationType = .Display
			nextChunkIndex += 1
			newChunk.parsedRange = results!.range
			newChunks.append(newChunk)
		}
		//look for MathML
		mathRegex.enumerateMatches(in: str, options: [], range: range)
		{ (results, _, _) -> Void in
			if str.substring(with: (results?.rangeAt(4).toStringRange(str))!) == "block" {
				let newChunk = DocumentChunk(chunkType: .equation, chunkNumber: 1)
				newChunk.equationType = .MathML
				newChunk.parsedRange = results!.range
				newChunks.append(newChunk)
			} else {
				inlineMathML.append(results!.range)
			}
		}
		//sort them by range
		newChunks = newChunks.sorted() { (chunk1, chunk2) in
			return chunk1.parsedRange.location < chunk2.parsedRange.location
		}
		//now loop through and add documentation chunks as needed
		var docChunks:[DocumentChunk] = []
		for (index, aChunk) in newChunks.enumerated() {
			let docChunk = DocumentChunk(chunkType: .documentation, chunkNumber: 1)
			if index == 0 { //first chunk
				if aChunk.parsedRange.location > 0 {
					docChunk.parsedRange = NSMakeRange(0, aChunk.parsedRange.location)
				}
			} else { //any other chunk
				let startIdx = MaxNSRangeIndex(newChunks[index-1].parsedRange)+1
				docChunk.parsedRange = NSMakeRange(startIdx, aChunk.parsedRange.location - startIdx)
			}
			docChunks.append(docChunk)
			docChunks.append(aChunk)
		}
		//add any text after the last docChunk
		if docChunks.count > 0 && MaxNSRangeIndex(docChunks.last!.parsedRange) < MaxNSRangeIndex(range) {
			let finalChunk = DocumentChunk(chunkType: .documentation, chunkNumber: 1)
			let loc = MaxNSRangeIndex(docChunks.last!.parsedRange) + 1
			finalChunk.parsedRange = NSMakeRange(loc, MaxNSRangeIndex(range) - loc)
			docChunks.append(finalChunk)
		}
		//renumber and sort by number
		var nextIdx = 0
		chunks = docChunks.enumerated().map() { (index, element) in
			nextIdx += 1
			return element.duplicateWithChunkNumber(nextIdx)
		}.sorted() { (chunk1, chunk2) -> Bool in
			return chunk1.chunkNumber < chunk2.chunkNumber
		}
		
		colorChunks(chunks)
		//set background of inline equations
		let color = colorMap[.InlineBackground]!
		inlineRegex.enumerateMatches(in: str, options: [], range: range)
		{ (results, _, _) -> Void in
			self.textStorage.addAttribute(NSBackgroundColorAttributeName, value: color, range: results!.range)
			self.latexHighlighter.highlightText(self.textStorage, range: results!.rangeAt(1))
		}
		for aRange in inlineMathML {
			self.textStorage.addAttribute(NSBackgroundColorAttributeName, value: color, range: aRange)
		}
		//highlight latex code in display equation blocks
		for aChunk in chunks {
			if aChunk.type == .rCode {
				self.latexHighlighter.highlightText(self.textStorage, range: aChunk.parsedRange)
			}
		}
	}
}
