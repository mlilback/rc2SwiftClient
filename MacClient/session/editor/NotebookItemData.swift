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
	public var chunk: DocumentChunk?
	
	public init(source: String, result: String) {
		self.source = NSTextStorage(attributedString: NSAttributedString(string: source))
		self.result = NSTextStorage(attributedString: NSAttributedString(string: result))
		super.init()
	}
}
