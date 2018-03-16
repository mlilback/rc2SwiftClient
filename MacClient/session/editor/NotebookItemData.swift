//
//  NotebookItemData.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import SyntaxParsing

public class NotebookItemData: NSObject {
	@objc public let source: NSTextStorage
	@objc public let result: NSTextStorage
	@objc public var height: CGFloat = 40
	public var chunk: DocumentChunk
	
	public init(chunk: DocumentChunk, source: String, result: String) {
		self.chunk = chunk
		let range = Range(chunk.parsedRange, in: source) ?? source.startIndex..<source.startIndex
		self.source = NSTextStorage(attributedString: NSAttributedString(string: String(source[range])))
		self.result = NSTextStorage(attributedString: NSAttributedString(string: result))
		super.init()
	}
}
