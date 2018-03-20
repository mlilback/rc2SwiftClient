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
	public var chunk: RmdChunk
	
	public init(chunk: RmdChunk, result: String) {
		self.chunk = chunk
		self.source = NSTextStorage(attributedString: chunk.attributedContents)
		self.result = NSTextStorage(attributedString: NSAttributedString(string: result))
		super.init()
	}
}
