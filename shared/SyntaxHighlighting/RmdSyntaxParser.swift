//
//  RmdSyntaxParser
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
#if os(OSX)
	import AppKit
#endif

class RmdSyntaxParser: SyntaxParser {
	let latexHighlighter:LatexCodeHighlighter = LatexCodeHighlighter()
	let rChunkRegex:NSRegularExpression
	let blockEqRegex: NSRegularExpression
	let inlineRegex:NSRegularExpression
	let mathRegex:NSRegularExpression
	
	override init(storage: NSTextStorage, fileType: FileType, colorMap: SyntaxColorMap)
	{
		try! rChunkRegex = NSRegularExpression(pattern: "\n```\\{r\\s*([^\\}]*)\\}\\s*\n+(.*?)\n```\n", options: .DotMatchesLineSeparators)
		try! blockEqRegex = NSRegularExpression(pattern: "(\\$\\$\\s*\\n+(.*?)\\$\\$)", options:.DotMatchesLineSeparators)
		try! inlineRegex = NSRegularExpression(pattern: "`r\\s+([^`]*)`", options: .DotMatchesLineSeparators)
		try! mathRegex = NSRegularExpression(pattern: "(<math(\\s+[^>]*)(display\\s*=\\s*\"(block|inline)\")([^>]*)>)(.*?)</math>\\s*?\\n?", options: .DotMatchesLineSeparators)
		
		super.init(storage: storage, fileType: fileType, colorMap: colorMap)
		codeHighlighter = RCodeHighlighter()
		colorBackgrounds = true
	}
	
	override func parseRange(range: NSRange) {
		let str = textStorage.string
		chunks.removeAll()
		var nextChunkIndex = 1
		var newChunks = [DocumentChunk]()
		var inlineMathML = [NSRange]()
		//add R code chunks
		rChunkRegex.enumerateMatchesInString(str, options: [], range: range)
		{ (result, flags, _) -> Void in
			var cname:String?
			if result?.rangeAtIndex(1).length > 0 {
				cname = str.substringWithRange(result!.rangeAtIndex(1).toStringRange(str)!)
			}
			let codeChunk = DocumentChunk(chunkType: .RCode, chunkNumber: nextChunkIndex, name: cname)
			nextChunkIndex += 1
			codeChunk.parsedRange = result!.rangeAtIndex(2)
			newChunks.append(codeChunk)
		}
		//add chunks for block equations
		blockEqRegex.enumerateMatchesInString(str, options: [], range: range)
		{ (results, _, _) -> Void in
			let newChunk = DocumentChunk(chunkType: .Equation, chunkNumber: nextChunkIndex)
			newChunk.equationType = .Display
			nextChunkIndex += 1
			newChunk.parsedRange = results!.range
			newChunks.append(newChunk)
		}
		//look for MathML
		mathRegex.enumerateMatchesInString(str, options: [], range: range)
		{ (results, _, _) -> Void in
			if str.substringWithRange((results?.rangeAtIndex(4).toStringRange(str))!) == "block" {
				let newChunk = DocumentChunk(chunkType: .Equation, chunkNumber: 1)
				newChunk.equationType = .MathML
				newChunk.parsedRange = results!.range
				newChunks.append(newChunk)
			} else {
				inlineMathML.append(results!.range)
			}
		}
		//sort them by range
		newChunks = newChunks.sort() { (chunk1, chunk2) in
			return chunk1.parsedRange.location < chunk2.parsedRange.location
		}
		//now loop through and add documentation chunks as needed
		var docChunks:[DocumentChunk] = []
		for (index, aChunk) in newChunks.enumerate() {
			let docChunk = DocumentChunk(chunkType: .Documentation, chunkNumber: 1)
			if index == 0 { //first chunk
				if aChunk.parsedRange.location > 0 {
					docChunk.parsedRange = NSMakeRange(0, aChunk.parsedRange.location-1)
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
			let finalChunk = DocumentChunk(chunkType: .Documentation, chunkNumber: 1)
			let loc = MaxNSRangeIndex(docChunks.last!.parsedRange) + 1
			finalChunk.parsedRange = NSMakeRange(loc, MaxNSRangeIndex(range) - loc)
			docChunks.append(finalChunk)
		}
		//renumber and sort by number
		var nextIdx = 0
		chunks = docChunks.enumerate().map() { (index, element) in
			nextIdx += 1
			return element.duplicateWithChunkNumber(nextIdx)
		}.sort() { (chunk1, chunk2) -> Bool in
			return chunk1.chunkNumber < chunk2.chunkNumber
		}
		
		colorChunks(chunks)
		//set background of inline equations
		var color = colorMap[.InlineBackground]!
		inlineRegex.enumerateMatchesInString(str, options: [], range: range)
		{ (results, _, _) -> Void in
			self.textStorage.addAttribute(NSBackgroundColorAttributeName, value: color, range: results!.range)
			self.latexHighlighter.highlightText(self.textStorage, range: results!.rangeAtIndex(1))
		}
		for aRange in inlineMathML {
			self.textStorage.addAttribute(NSBackgroundColorAttributeName, value: color, range: aRange)
		}
		//highlight latex code in display equation blocks
		color = colorMap[.EquationBackground]!
		for aChunk in chunks {
			if aChunk.type == .Equation && aChunk.equationType == .Display {
				self.latexHighlighter.highlightText(self.textStorage, range: aChunk.parsedRange)
			}
		}
	}
}
