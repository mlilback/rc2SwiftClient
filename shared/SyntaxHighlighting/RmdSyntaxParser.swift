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
	let chunkRegex:NSRegularExpression
	let inlineRegex:NSRegularExpression
	let equationRegex:NSRegularExpression
	let jaxRegex:NSRegularExpression
	
	override init(storage: NSTextStorage, fileType: FileType, colorMap: SyntaxColorMap)
	{
		try! chunkRegex = NSRegularExpression(pattern: "\n```\\{r\\s*([^\\}]*)\\}\\s*\n+(.*?)\n```\n", options: .DotMatchesLineSeparators)
		try! inlineRegex = NSRegularExpression(pattern: "`r\\s+([^`]*)`", options: .DotMatchesLineSeparators)
		try! equationRegex = NSRegularExpression(pattern: "(?:(\\$\\$?)(?:latex)?(.*?)(\\1))", options: .DotMatchesLineSeparators)
		try! jaxRegex = NSRegularExpression(pattern: "(?:\\\\\\{\\s+(.*?)\\\\\\})|(\\\\\\(\\s+(.*?)\\\\\\))", options: .DotMatchesLineSeparators)
		
		super.init(storage: storage, fileType: fileType, colorMap: colorMap)
		codeHighlighter = RCodeHighlighter()
	}
	
	override func parseRange(range: NSRange) {
		let str = textStorage.string
		chunks.removeAll()
		var docBlockStart = 0
		var nextChunkIndex = 1
		chunkRegex.enumerateMatchesInString(str, options: [], range: range)
		{ (result, flags, _) -> Void in
			//if there is a previous chunk, add it (e.g. the file starts with a documentation block)
			if result!.range.location - docBlockStart > 0 {
				let docChunk = DocumentChunk(chunkType: .Documentation, chunkNumber: nextChunkIndex)
				nextChunkIndex += 1
				docChunk.parseRange = NSMakeRange(docBlockStart, result!.range.location - docBlockStart)
				self.chunks.append(docChunk)
			}
			var cname:String?
			if result?.rangeAtIndex(1).length > 0 {
				cname = str.substringWithRange(result!.rangeAtIndex(1).toStringRange(str)!)
			}
			let codeChunk = DocumentChunk(chunkType: .RCode, chunkNumber: nextChunkIndex, name: cname)
			nextChunkIndex += 1
			codeChunk.parseRange = result!.rangeAtIndex(2)
			self.chunks.append(codeChunk)
			docBlockStart = result!.range.location + result!.range.length
		}
		//if there is a documentation block after the last code block
		if docBlockStart < str.utf8.count {
			let finalChunk = DocumentChunk(chunkType: .Documentation, chunkNumber: nextChunkIndex)
			finalChunk.parseRange = NSMakeRange(docBlockStart, str.utf8.count - docBlockStart)
			chunks.append(finalChunk)
		}
		
		colorChunks(chunks)
		var color = colorMap[.InlineBackground]!
		inlineRegex.enumerateMatchesInString(str, options: [], range: range)
		{ (results, _, _) -> Void in
			self.textStorage.addAttribute(NSBackgroundColorAttributeName, value: color, range: results!.range)
			self.codeHighlighter?.highlightText(self.textStorage, range: results!.rangeAtIndex(1))
		}
		color = colorMap[.EquationBackground]!
		equationRegex.enumerateMatchesInString(str, options: [], range: range)
		{ (results, _, _) -> Void in
			self.textStorage.addAttribute(NSBackgroundColorAttributeName, value: color, range: results!.range)
			self.codeHighlighter?.highlightText(self.textStorage, range: results!.rangeAtIndex(1))
		}
		jaxRegex.enumerateMatchesInString(str, options: [], range: range)
		{ (results, _, _) -> Void in
			self.textStorage.addAttribute(NSBackgroundColorAttributeName, value: color, range: results!.range)
			self.codeHighlighter?.highlightText(self.textStorage, range: results!.rangeAtIndex(1))
		}
	}
}
