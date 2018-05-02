//
//  RmdDocument.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Model
import MJLLogger
import ReactiveSwift
import Result

public enum ParserError: Error {
	case failedToParse
	case inlineEquationNotInTextChunk
}
public typealias HasHelpCallback = (String) -> Bool
public typealias ParserErrorHandler = (ParserError) -> Void

public class RmdDocument {
	/// Chunks comprising this document:
	public var chunks: [RmdChunk] { return _chunks.value }
	/// A Property of a protocol (RmdChunk) can't observer changes to a mutableproperty
	/// of a concrete type. Instead, this signal is mapped to changes in the chunks array:
	public let chunksSignal: Signal<[RmdChunk], NoError>
	private let chunksObserver: Signal<[RmdChunk], NoError>.Observer
	/// Front matter:
	public let frontMatter = MutableProperty("")
	// Private:
	private let _chunks = MutableProperty<[InternalRmdChunk]>([])
	private var textStorage = NSTextStorage()
	private var parser: SyntaxParser
	
	/// Creates a structure document.
	///
	/// - Parameters:
	///   - contents: initial contents of the document
	///   - helpCallback: callback that returns true if a term should be highlighted as a help term
	public init(contents: String, helpCallback: @escaping  HasHelpCallback) throws {
		(chunksSignal, chunksObserver) = Signal<[RmdChunk], NoError>.pipe()
		textStorage.append(NSAttributedString(string: contents))
		let filetype = FileType.fileType(withExtension: "Rmd")!
		parser = SyntaxParser(storage: textStorage, fileType: filetype, helpCallback: helpCallback)
		_chunks.signal.observeValues { [weak self] val in self?.chunksObserver.send(value: val) }
		parser.parse()
		frontMatter.value = parser.frontMatter
		var lastTextChunk: MarkdownChunk?
		var lastWasInline: Bool = false
		try parser.chunks.forEach { parserChunk in
			switch parserChunk.chunkType {
			case .docs:
				let chunkContents = parser.textStorage.attributedSubstring(from: parserChunk.innerRange)
				let whitespaceOnly = chunkContents.string.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted) == nil
				if lastWasInline || whitespaceOnly {
					// need to append this chunk's content to lastTextChunk
					lastTextChunk?.textStorage.append(chunkContents)
					lastWasInline = false
					return
				}
				let tchunk = MarkdownChunk(parser: parser, contents: parser.textStorage, range: parserChunk.innerRange)
				append(chunk: tchunk)
				lastTextChunk = tchunk
				lastWasInline = false
			case .code:
				let cchunk = CodeChunk(parser: parser, contents: parser.textStorage, range: parserChunk.innerRange, options: parserChunk.rOps)
				if parserChunk.isInline, let lastChunk = lastTextChunk {
					let achunk = InternalInlineCodeChunk(parser: parser, contents: parser.textStorage, range: parserChunk.innerRange, options: parserChunk.rOps)
					attach(chunk: achunk, to: lastChunk.textStorage)
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
					let dchunk = InternalInlineEquation(parser: parser, contents: parser.textStorage, range: parserChunk.innerRange)
					lastChunk.inlineElements.append(dchunk)
					attach(chunk: dchunk, to: lastChunk.textStorage)
					lastWasInline = true
				case .display:
					let dchunk = EquationChunk(parser: parser, contents: parser.textStorage, range: parserChunk.parsedRange, innerRange: parserChunk.innerRange)
					append(chunk: dchunk)
					lastTextChunk = nil
					lastWasInline = false
				case .mathML:
					print("MathML not supported yet")
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
		_chunks.value.append(chunk)
	}
	
	public func moveChunk(from startIndex: Int, to endIndex: Int) {
		assert(startIndex >= 0)
		assert(endIndex >= 0) //don't check high constraint because anything larger than count will move to end
		guard startIndex != endIndex else { return }
		var tmpChunks = _chunks.value
		defer { _chunks.value = tmpChunks }
		if endIndex >= tmpChunks.count {
			let elem = tmpChunks[startIndex]
			tmpChunks.remove(at: startIndex)
			tmpChunks.append(elem)
		} else if endIndex > startIndex {
			let elem = tmpChunks.remove(at: startIndex)
			tmpChunks.insert(elem, at: endIndex - 1)
		} else {
			let elem = tmpChunks.remove(at: startIndex)
			tmpChunks.insert(elem, at: endIndex)
		}
	}
	
	public func insertChunk(type: ChunkType, contents: String, at index: Int) {
		let chunk: InternalRmdChunk
		switch type {
		case .code:
			chunk = CodeChunk(parser: parser, contents: contents, range: contents.fullNSRange, options: nil)
		case .docs:
			chunk = MarkdownChunk(parser: parser, contents: contents, range: contents.fullNSRange)
		case .equation:
			let fullContents = "$$\n\(contents)\n$$\n"
			chunk = EquationChunk(parser: parser, contents: fullContents, range: contents.fullNSRange, innerRange: NSRange(location: 3, length: contents.count))
		}
		_chunks.value.insert(chunk, at: index)
	}
	
	public func insertTextChunk(initalContents: String, at index: Int) {
		let chunk = MarkdownChunk(parser: parser, contents: initalContents, range: initalContents.fullNSRange)
		_chunks.value.insert(chunk, at: index)
	}

	public func insertCodeChunk(initalContents: String, at index: Int) {
		let chunk = CodeChunk(parser: parser, contents: initalContents, range: initalContents.fullNSRange, options: nil)
		_chunks.value.insert(chunk, at: index)
	}

	public func insertEquationChunk(initalContents: String, at index: Int) {
		let chunk = EquationChunk(parser: parser, contents: initalContents, range: initalContents.fullNSRange, innerRange: initalContents.fullNSRange)
		_chunks.value.insert(chunk, at: index)
	}
}

// MARK: - protocols

public protocol Equation: class {}

public protocol Code: class {
	var options: MutableProperty<String> { get }
}

public protocol RmdChunk: class {
	var contents: NSAttributedString { get set }
	var chunkType: ChunkType { get }
	var rawText: String { get }
}

public protocol InlineChunk: RmdChunk {}

public protocol TextChunk: RmdChunk {
	var inlineElements: [InlineChunk] { get }
}

public typealias InlineEquationChunk = InlineChunk & Equation

// MARK: - attachments
public class InlineAttachment: NSTextAttachment {
	public internal(set) weak var chunk: InlineChunk?
}

class InlineAttachmentCell: NSTextAttachmentCell {
	override func cellFrame(for textContainer: NSTextContainer, proposedLineFragment lineFrag: NSRect, glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
		var rect = super.cellFrame(for: textContainer, proposedLineFragment: lineFrag, glyphPosition: position, characterIndex: charIndex)
		// why does magic number work for all font sizes?
		rect.origin.y = -5
		return rect
	}
}

// MARK: - chunks

class InternalRmdChunk: NSObject, RmdChunk, ChunkProtocol, NSTextStorageDelegate {
	weak var parser: SyntaxParser?
	var textStorage: NSTextStorage
	let chunkType: ChunkType
	let docType: DocType
	let equationType: EquationType
	private var ignoreTextChanges = false
	
	var contents: NSAttributedString {
		get { return textStorage.attributedSubstring(from: textStorage.string.fullNSRange) }
		set { update(text: newValue) }
	}
	
	var rawText: String { return textStorage.string }
	
	init(parser: SyntaxParser, chunk: DocumentChunk) {
		self.parser = parser
		self.chunkType = chunk.chunkType
		self.docType = chunk.docType
		self.equationType = chunk.equationType
		textStorage = NSTextStorage()
		super.init()
		textStorage.delegate = self
	}

	func update(text: NSAttributedString) {
		guard !ignoreTextChanges else { return }
		ignoreTextChanges = true
		defer { ignoreTextChanges = false }
		textStorage.replace(with: text)
		highlight(attributedString: textStorage)
	}
	
	// Called when text editing has ended:
	public func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int)
	{
		// We don't care if attributes changed.
		guard editedMask.contains(.editedCharacters) else { return }
		guard !ignoreTextChanges else { return }
		Log.debug("did edit: \(textStorage.string.substring(from: editedRange) ?? "")", .core)
		highlight(attributedString: textStorage)
	}
}

// MARK: -
class MarkdownChunk: InternalRmdChunk, TextChunk {
	var inlineElements: [InlineChunk]
	let origText: String
	
	init(parser: SyntaxParser, contents: NSAttributedString, range: NSRange) {
		// Use a fake chunk to create from contents.
		let pchunk = DocumentChunk(chunkType: .docs, docType: .rmd, equationType: .none,
								   range: range, innerRange: range, chunkNumber: 1)
		inlineElements = []
		origText = contents.string.substring(from: range)!
		super.init(parser: parser, chunk: pchunk)
		update(text: contents.attributedSubstring(from: range))
	}
	
	init(parser: SyntaxParser, contents: String, range: NSRange) {
		// Use a fake chunk to create from contents.
		let pchunk = DocumentChunk(chunkType: .docs, docType: .rmd, equationType: .none,
								   range: range, innerRange: range, chunkNumber: 1)
		inlineElements = []
		origText = contents.substring(from: range)!
		super.init(parser: parser, chunk: pchunk)
		update(text: NSAttributedString(string: contents.substring(from: range)!))
		highlight(attributedString: textStorage, inRange: pchunk.innerRange)
	}
	
	override var rawText: String {
		// Need to replace attachments with their rawText.
		let tmpAttrStr = NSMutableAttributedString(attributedString: textStorage)
		// FIXME: needs to handle code chunks, likely via method on inline attachment class that returns the equiv of iContents
		tmpAttrStr.enumerateAttribute(.attachment, in: tmpAttrStr.string.fullNSRange, options: [])
		{ (attrValue, attrRange, stop) in
			guard attrValue != nil else { return }
			guard let iAttach = attrValue as? InlineAttachment,
				let iChunk = iAttach.chunk
				else { tmpAttrStr.deleteCharacters(in: attrRange); return }
			let iContents = NSMutableAttributedString(attributedString: iChunk.contents)
			let dollar = NSAttributedString(string: "$")
			iContents.insert(dollar, at: 0)
			iContents.append(dollar)
			tmpAttrStr.replaceCharacters(in: attrRange, with: iContents)
		}
		let val = tmpAttrStr.string
		return val
	}
}

// MARK: -
class CodeChunk: InternalRmdChunk, Code {
	var options: MutableProperty<String>
	init(parser: SyntaxParser, contents: NSAttributedString, range: NSRange, options: String?) {
		self.options = MutableProperty<String>(options ?? "")
		let pchunk = DocumentChunk(chunkType: .code, docType: .rmd, equationType: .none,
								   range: range, innerRange: range, chunkNumber: 1)
		super.init(parser: parser, chunk: pchunk)
		update(text: contents.attributedSubstring(from: range))
	}

	init(parser: SyntaxParser, contents: String, range: NSRange, options: String?) {
		self.options = MutableProperty<String>(options ?? "")
		let pchunk = DocumentChunk(chunkType: .code, docType: .rmd, equationType: .none,
								   range: range, innerRange: range, chunkNumber: 1)
		super.init(parser: parser, chunk: pchunk)
		update(text: NSAttributedString(string: contents.substring(from: range)!))
	}

	override var rawText: String {
		var opts = options.value
		if opts.count > 0 { opts = " " + opts }
		return textStorage.string.surroundWithoutAddingNewlines(startText: "```{r\(opts)}", endText: "```")
	}
}

// MARK: -
class EquationChunk: InternalRmdChunk, Equation {
	init(parser: SyntaxParser, contents: NSAttributedString, range: NSRange, innerRange: NSRange) {
		let pchunk = DocumentChunk(chunkType: .equation, docType: .latex, equationType: .display,
								   range: range, innerRange: innerRange, chunkNumber: 1)
		super.init(parser: parser, chunk: pchunk)
		// FIXME: notebook was blowing up with attributed equations
//		let eqstr = contents.attributedSubstring(from: range)
		let eqstr = NSAttributedString(string: contents.string.substring(from: innerRange)!.appending("\n"))
		update(text: eqstr)
	}

	init(parser: SyntaxParser, contents: String, range: NSRange, innerRange: NSRange) {
		let pchunk = DocumentChunk(chunkType: .equation, docType: .latex, equationType: .display,
								   range: range, innerRange: innerRange, chunkNumber: 1)
		super.init(parser: parser, chunk: pchunk)
		let eqstr = NSAttributedString(string: contents.substring(from: innerRange)!)
		update(text: eqstr)
	}
	
	override var rawText: String {
		let str = textStorage.string.trimmingCharacters(in: .newlines)
		return str.surroundWithoutAddingNewlines(startText: "$$", endText: "$$")
	}
}

// MARK: -

class InternalInlineEquation: InternalRmdChunk, InlineChunk, Equation {
	init(parser: SyntaxParser, contents: NSAttributedString, range: NSRange) {
		let pchunk = DocumentChunk(chunkType: .equation, docType: .latex, equationType: .inline,
								   range: range, innerRange: range, chunkNumber: 1)
		super.init(parser: parser, chunk: pchunk)
		// FIXME: this was breaking things
//		update(text: contents.attributedSubstring(from: range))
		update(text: NSAttributedString(string: contents.string.substring(from: range)!))
	}

	init(parser: SyntaxParser, contents: String, range: NSRange) {
		let pchunk = DocumentChunk(chunkType: .equation, docType: .latex, equationType: .inline,
								   range: range, innerRange: range, chunkNumber: 1)
		super.init(parser: parser, chunk: pchunk)
		update(text: NSAttributedString(string: contents.substring(from: range)!))
	}
}

class InternalInlineCodeChunk: InternalRmdChunk, InlineChunk, Code {
	var options: MutableProperty<String>
	init(parser: SyntaxParser, contents: NSAttributedString, range: NSRange, options: String) {
		self.options = MutableProperty<String>(options)
		let pchunk = DocumentChunk(chunkType: .code, docType: .rmd, equationType: .none,
								   range: range, innerRange: range, chunkNumber: 1)
		super.init(parser: parser, chunk: pchunk)
		update(text: contents.attributedSubstring(from: range))
	}
}

public extension String {
	/// surrounds self with startText and endText, only adding newlines if none already exist
	public func surroundWithoutAddingNewlines(startText: String, endText: String) -> String {
		var contents = ""
		contents += startText
		if !self.hasPrefix("\n") { contents += "\n" }
		contents += self
		if !self.hasSuffix("\n") { contents += "\n" }
		contents += endText
		contents += "\n"
		return contents
	}
}
