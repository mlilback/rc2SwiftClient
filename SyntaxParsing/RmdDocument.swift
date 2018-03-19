//
//  RmdDocument.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Model
import MJLLogger

public typealias ParserErrorHandler = (ParserError) -> Void

public class RmdDocument {
	/// the chunks comprising this document
	public var chunks: [RmdChunk] { return internalChunks }
	/// front matter
	public private(set) var frontMatter: String = ""
	
	private var internalChunks: [InternalRmdChunk] = []
	private var textStorage = NSTextStorage()
	private var parser: BaseSyntaxParser
	
	/// create a structure document
	///
	/// - Parameters:
	///   - contents: initial contents of the document
	///   - helpCallback: callback that returns true if a term should be highlighted as a help term
	public init(contents: String, helpCallback: @escaping  HasHelpCallback) throws {
		textStorage.append(NSAttributedString(string: contents))
		parser = BaseSyntaxParser.parserWithTextStorage(textStorage, fileType: FileType.fileType(withExtension: "Rmd")!, helpCallback: helpCallback)!
		parser.parse()
		var lastTextChunk: InternalTextChunk?
		var lastWasInline: Bool = false
		try parser.chunks.forEach { parserChunk in
			switch parserChunk.chunkType {
			case .docs:
				if lastWasInline {
					// need to append this chunk's content to lastTextChunk
					lastTextChunk?.storage.append(parser.textStorage.attributedSubstring(from: parserChunk.parsedRange))
					lastWasInline = false
					return
				}
				let tchunk = InternalTextChunk(parser: parser, contents: parser.textStorage.string, range: parserChunk.parsedRange)
				internalChunks.append(tchunk)
				lastTextChunk = tchunk
				lastWasInline = false
			case .code:
				let cchunk = InternalCodeChunk(parser: parser, contents: parser.textStorage.string, range: parserChunk.parsedRange)
				internalChunks.append(cchunk)
				lastTextChunk = nil
				lastWasInline = false
			case .equation:
				switch parserChunk.equationType {
				case .none: fatalError()
				case .inline:
					guard let lastChunk = lastTextChunk else { throw ParserError.inlineEquationNotInTextChunk }
					let dchunk = InternalInlineEquation(parser: parser, contents: parser.textStorage.string, range: parserChunk.parsedRange)
					lastChunk.inlineElements.append(dchunk)
					lastChunk.storage.append(NSAttributedString(string: attachmentString, attributes: [attachmentKey: InlineAttachment(dchunk)]))
					lastWasInline = true
				case .display:
					let dchunk = InternalEquationChunk(parser: parser, contents: parser.textStorage.string, range: parserChunk.parsedRange)
					internalChunks.append(dchunk)
					lastTextChunk = nil
					lastWasInline = false
				case .mathML:
					fatalError("MathML not supported yet")
				}
			}
		}
	}
	
	public func moveChunk(from startIndex: Int, to endIndex: Int) {
		assert(startIndex >= 0)
		assert(endIndex >= 0) //don't check high constraint because anything larger than count will move to end
		guard startIndex != endIndex else { return }
		if endIndex >= internalChunks.count {
			let elem = internalChunks[startIndex]
			internalChunks.remove(at: startIndex)
			internalChunks.append(elem)
			return
		} else if endIndex > startIndex {
			let elem = internalChunks.remove(at: startIndex)
			internalChunks.insert(elem, at: endIndex - 1)
		} else {
			let elem = internalChunks.remove(at: startIndex)
			internalChunks.insert(elem, at: endIndex)
		}
	}
	
	public func insertTextChunk(initalContents: String, at index: Int) {
		let chunk = InternalTextChunk(parser: parser, contents: initalContents, range: initalContents.fullNSRange)
		internalChunks.insert(chunk, at: index)
	}

	public func insertCodeChunk(initalContents: String, at index: Int) {
		let chunk = InternalCodeChunk(parser: parser, contents: initalContents, range: initalContents.fullNSRange)
		internalChunks.insert(chunk, at: index)
	}

	public func insertEquationChunk(initalContents: String, at index: Int) {
		let chunk = InternalEquationChunk(parser: parser, contents: initalContents, range: initalContents.fullNSRange)
		internalChunks.insert(chunk, at: index)
	}
}

public protocol Equation: class {
	var equationSource: String { get }
}
public protocol Code: class {}
public protocol RmdChunk: class {
	var contents: String { get }
}
public protocol InlineChunk: RmdChunk {}

public protocol TextChunk: RmdChunk {
	var inlineElements: [InlineChunk] { get }
}

public protocol CodeChunk: RmdChunk {
}

// MARK: -
let attachmentString = "⚓︎"
let attachmentKey = NSAttributedStringKey("rc2.InlineChunk")
struct InlineAttachment {
	weak var chunk: InlineChunk?
	init(_ value: InlineChunk) {
		chunk = value
	}
}

class InternalRmdChunk: NSObject, RmdChunk, NSTextStorageDelegate {
	weak var parser: BaseSyntaxParser?
	var parserChunk: DocumentChunk
	var storage: NSTextStorage
	
	public var contents: String { return storage.string }
	public var attributedContents: NSAttributedString { return NSAttributedString(attributedString: storage) }
	
	init(parser: BaseSyntaxParser, chunk: DocumentChunk) {
		self.parser = parser
		self.parserChunk = chunk
		storage = NSTextStorage()
		super.init()
		storage.delegate = self
	}

	// called when text editing has ended
	public func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int)
	{
		//we don't care if attributes changed
		guard editedMask.contains(.editedCharacters) else { return }
		parser?.colorChunks([parserChunk])
	}
}

// MARK: -
class InternalTextChunk: InternalRmdChunk, TextChunk {
	var inlineElements: [InlineChunk]
	
	init(parser: BaseSyntaxParser, contents: String, range: NSRange) {
		let pchunk = DocumentChunk(chunkType: .docs, docType: .rmd, equationType: .none, range: range, chunkNumber: 1)
		inlineElements = []
		super.init(parser: parser, chunk: pchunk)
		storage.append(NSAttributedString(string: contents.substring(from: range)!))
	}
	
	override var attributedContents: NSAttributedString {
		let out = NSMutableAttributedString(attributedString: storage)
		storage.enumerateAttribute(attachmentKey, in: out.string.fullNSRange, options: [.reverse])
		{ (value, attrRange, stopPtr) in
			guard let ival = value as? InlineAttachment, let chunk = ival.chunk as? InternalRmdChunk else { return }
			out.replaceCharacters(in: attrRange, with: chunk.storage)
		}
		return out
	}
	
	override var contents: String { return attributedContents.string }
}

// MARK: -
class InternalCodeChunk: InternalRmdChunk, Code {
	
	init(parser: BaseSyntaxParser, contents: String, range: NSRange) {
		let pchunk = DocumentChunk(chunkType: .code, docType: .rmd, equationType: .none, range: range, chunkNumber: 1)
		super.init(parser: parser, chunk: pchunk)
		storage.append(NSAttributedString(string: contents.substring(from: range)!))
	}
}

// MARK: -
class InternalEquationChunk: InternalRmdChunk, Equation {
	var equationSource: String {
		return storage.string.substring(from: NSRange(location: 2, length: storage.length - 4))!
	}
	
	init(parser: BaseSyntaxParser, contents: String, range: NSRange) {
		let pchunk = DocumentChunk(chunkType: .equation, docType: .latex, equationType: .display, range: range, chunkNumber: 1)
		super.init(parser: parser, chunk: pchunk)
		storage.append(NSAttributedString(string: contents))
	}
}

// MARK:

class InternalInlineEquation: InternalRmdChunk, InlineChunk, Equation {
	var equationSource: String {
		return storage.string.substring(from: NSRange(location: 1, length: storage.length - 2))!
	}

	init(parser: BaseSyntaxParser, contents: String, range: NSRange) {
		let pchunk = DocumentChunk(chunkType: .equation, docType: .latex, equationType: .inline, range: range, chunkNumber: 1)
		super.init(parser: parser, chunk: pchunk)
		storage.append(NSAttributedString(string: contents.substring(from: range)!))
	}
}

//public class InlineCode: InlineChunk, Code {
//	
//}

