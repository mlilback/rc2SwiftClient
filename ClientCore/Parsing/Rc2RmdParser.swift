//
//  Rc2RmdParser.swift
//  ClientCore
//
//  Created by Mark Lilback on 12/17/19.
//  Copyright © 2019 Rc2. All rights reserved.
//

import Foundation
import Parsing
import ReactiveSwift
import Rc2Common
import MJLLogger

/// a callback that recieves a parsed keyword. returns true if a help URL should be included for it
public typealias HelpCallback = (String) -> Bool

/// for  instances where write access is not needed
public protocol ParserContext {
	var parsedDocument: Property<RmdDocument?> { get }
}

/// A wrapper around parsing so users of ClientCore do not need to know about Rc2Parser
public class Rc2RmdParser: RmdParser, ParserContext {
	var helpCallback: HelpCallback?
	private var contents: NSTextStorage
	// offers read-only version of _parsedDocument
	public let parsedDocument: Property<RmdDocument?>
	private let _parsedDocument = MutableProperty<RmdDocument?>(nil)
	
	public init(contents: NSTextStorage, help: @escaping HelpCallback) {
		self.contents = contents
		helpCallback = help
		parsedDocument = Property<RmdDocument?>(_parsedDocument)
		super.init()
	}
	
	/// Reparses the contents and updates parsedDocument, syntax highlighting any R code
	public func reparse() throws {
		guard contents.length > 0 else { _parsedDocument.value = nil; return }
		_parsedDocument.value = try RmdDocument(contents: contents.string, parser: self)
		// highlight code chunks
		_parsedDocument.value?.chunks.forEach { chunk in
			contents.addAttribute(ChunkKey, value: chunk.chunkType, range: chunk.innerRange)
			chunk.children.forEach { contents.addAttribute(ChunkKey, value: $0.chunkType, range: $0.innerRange)} // mark nested chunks
			if chunk.isEquation {
				highlightLatex(contents: contents, range: chunk.innerRange)
				return
			}
			guard chunk.chunkType == .code else { return }
			do {
				try highlightR(contents: contents, range: chunk.innerRange)
			} catch {
				Log.error("error highlighting R code \(error.localizedDescription)", .parser)
				Log.debug("code=\(contents.attributedSubstring(from: chunk.innerRange).string)", .parser)
			}
		}
	}
	
	/// Highlights the  code/equations of text in range.
	///  - Note: only currently called for R documents, so does not need to handle latex code
	/// - Parameters:
	///   - text: The mutable attributed string to update highlight of
	///   - range: The range to update, niil updates the entire text
	public func highlight(text: NSMutableAttributedString, range: NSRange? = nil) {
		let rng = range ?? NSRange(location: 0, length: text.length)
		do {
			try highlightR(contents: text, range: rng)
		} catch {
			Log.warn("error message highlighting R code", .app)
		}
	}

	public func selectionChanged(range: NSRange) {
		try! reparse()
	}
	
	/// Called when the contents of the editor have changed due to user action. By default, this parses and highlights the entire contents
	///
	/// - Parameters:
	///   - contents: The contents of the editor that was changed
	///   - range: the range of the original text that changed
	///   - delta: the length delta for the edited change
	public func contentsChanged(range: NSRange, changeLength delta: Int) {
		highlight(text: contents, range: range)
	}
}
