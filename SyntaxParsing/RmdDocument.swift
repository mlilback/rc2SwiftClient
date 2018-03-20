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
				let chunkContents = parser.textStorage.attributedSubstring(from: parserChunk.parsedRange)
				let whitespaceOnly = chunkContents.string.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted) == nil
				if lastWasInline || whitespaceOnly {
					// need to append this chunk's content to lastTextChunk
					lastTextChunk?.storage.append(chunkContents)
					lastWasInline = false
					return
				}
				let tchunk = InternalTextChunk(parser: parser, contents: parser.textStorage.string, range: parserChunk.parsedRange)
				append(chunk: tchunk)
				lastTextChunk = tchunk
				lastWasInline = false
			case .code:
				let cchunk = InternalCodeChunk(parser: parser, contents: parser.textStorage.string, range: parserChunk.parsedRange)
				if parserChunk.isInline, let lastChunk = lastTextChunk {
					let achunk = InternalInlineCodeChunk(parser: parser, contents: parser.textStorage.string, range: parserChunk.parsedRange)
					attach(chunk: achunk, to: lastChunk.storage)
					lastWasInline = true
					return
				}
				append(chunk: cchunk)
				lastWasInline = parserChunk.isInline
				if !lastWasInline { lastTextChunk = nil }
			case .equation:
				switch parserChunk.equationType {
				case .none: fatalError()
				case .inline:
					guard let lastChunk = lastTextChunk else { throw ParserError.inlineEquationNotInTextChunk }
					let dchunk = InternalInlineEquation(parser: parser, contents: parser.textStorage.string, range: parserChunk.parsedRange)
					lastChunk.inlineElements.append(dchunk)
					attach(chunk: dchunk, to: lastChunk.storage)
					lastWasInline = true
				case .display:
					let dchunk = InternalEquationChunk(parser: parser, contents: parser.textStorage.string, range: parserChunk.parsedRange)
					append(chunk: dchunk)
					lastTextChunk = nil
					lastWasInline = false
				case .mathML:
					fatalError("MathML not supported yet")
				}
			}
		}
	}
	
	private func attach(chunk: InlineChunk, to storage: NSTextStorage) {
		let attach = InlineAttachment()
		attach.chunk = chunk
		let image = chunk is Equation ? #imageLiteral(resourceName: "inlineEquation") : #imageLiteral(resourceName: "inlineCode")
		let acell = InlineAttachmentCell(imageCell: image)
		attach.bounds = CGRect(origin: CGPoint(x: 0, y: -5), size: acell.image!.size)
		attach.attachmentCell = acell
		storage.append(NSAttributedString(attachment: attach))
	}
	
	private func append(chunk: InternalRmdChunk) {
		internalChunks.append(chunk)
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
public protocol Code: class {
	var codeSource: String { get }
}
public protocol RmdChunk: class {
	var contents: String { get }
	var attributedContents: NSAttributedString { get }
	var chunkType: ChunkType { get }
	
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
class InlineAttachment: NSTextAttachment {
	weak var chunk: InlineChunk?
	
//	override func attachmentBounds(for textContainer: NSTextContainer?, proposedLineFragment lineFrag: NSRect, glyphPosition position: CGPoint, characterIndex charIndex: Int) -> NSRect {
//		let font = textContainer?.textView?.font ?? NSFont.userFixedPitchFont(ofSize: 14.0)
//		let height = lineFrag.size.height
//		var scale: CGFloat = 1.0
//		let imageSize = image!.size
//		if (height < imageSize.height) {
//			scale = CGFloat(height / imageSize.height)
//		}
//		print("returning size")
//		return CGRect(x: 0, y: 15, width: imageSize.width * scale, height: imageSize.height * scale)
////		return CGRect(x: 0, y: (font!.capHeight - imageSize.height).rounded() / 2, width: imageSize.width * scale, height: imageSize.height * scale)
//	}
}

class InlineAttachmentCell: NSTextAttachmentCell {
	override func cellFrame(for textContainer: NSTextContainer, proposedLineFragment lineFrag: NSRect, glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
		var rect = super.cellFrame(for: textContainer, proposedLineFragment: lineFrag, glyphPosition: position, characterIndex: charIndex)
		// why does magic number work for all font sizes?
		rect.origin.y = -5
		return rect
	}
}
class InternalRmdChunk: NSObject, RmdChunk, NSTextStorageDelegate {
	weak var parser: BaseSyntaxParser?
	var parserChunk: DocumentChunk
	var storage: NSTextStorage
	var chunkType: ChunkType { return .docs }
	
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
//		storage.enumerateAttribute(.attachment, in: out.string.fullNSRange, options: [.reverse])
//		{ (value, attrRange, stopPtr) in
//			guard let ival = value as? InlineAttachment,
//				let chunk = ival.chunk as? InternalRmdChunk,
//				let cell = ival.attachmentCell as? NSCell
//			else { return }
//			out.replaceCharacters(in: attrRange, with: chunk.storage)
//		}
		return out
	}
	
	override var contents: String { return attributedContents.string }
}

// MARK: -
class InternalCodeChunk: InternalRmdChunk, Code {
	var codeSource: String { return contents }
	
	override var chunkType: ChunkType { return .code }
	init(parser: BaseSyntaxParser, contents: String, range: NSRange) {
		let pchunk = DocumentChunk(chunkType: .code, docType: .rmd, equationType: .none, range: range, chunkNumber: 1)
		super.init(parser: parser, chunk: pchunk)
		storage.append(NSAttributedString(string: contents.substring(from: range)!))
	}
}

// MARK: -
class InternalEquationChunk: InternalRmdChunk, Equation {
	override var chunkType: ChunkType { return .equation }
	var equationSource: String {
		return storage.string.substring(from: NSRange(location: 2, length: storage.length - 4))!
	}
	
	init(parser: BaseSyntaxParser, contents: String, range: NSRange) {
		let pchunk = DocumentChunk(chunkType: .equation, docType: .latex, equationType: .display, range: range, chunkNumber: 1)
		super.init(parser: parser, chunk: pchunk)
		storage.append(NSAttributedString(string: contents.substring(from: range)!))
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

class InternalInlineCodeChunk: InternalRmdChunk, InlineChunk, Code {
	var codeSource: String { return contents }
	
	init(parser: BaseSyntaxParser, contents: String, range: NSRange) {
		let pchunk = DocumentChunk(chunkType: .code, docType: .rmd, equationType: .none, range: range, chunkNumber: 1)
		super.init(parser: parser, chunk: pchunk)
		storage.append(NSAttributedString(string: contents.substring(from: range)!))
	}
}

