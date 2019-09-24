//
//  RmdDocument.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Model
import MJLLogger
import ReactiveSwift

public enum ParserError: Error {
	case failedToParse
	case inlineEquationNotInTextChunk
}
public typealias HasHelpCallback = (String) -> Bool
public typealias ParserErrorHandler = (ParserError) -> Void

public class RmdDocument: CustomDebugStringConvertible {
	/// Chunks comprising this document:
	public var chunks: [RmdChunk] { return _chunks.value }
	/// A Property of a protocol (RmdChunk) can't observer changes to a mutableproperty
	/// of a concrete type. Instead, this signal is mapped to changes in the chunks array:
	public let chunksSignal: Signal<[RmdChunk], Never>
	private let chunksObserver: Signal<[RmdChunk], Never>.Observer
	/// Front matter:
	public let frontMatter = MutableProperty("")
	// Private:
	private let _chunks = MutableProperty<[InternalRmdChunk]>([])
	private var textStorage = NSTextStorage()
	private var parser: SyntaxParser
	
	public var debugDescription: String { return "RmdDocument with \(_chunks.value.count) chunks" }
	
	/// Creates a structure document.
	///
	/// - Parameters:
	///   - contents: initial contents of the document
	///   - helpCallback: callback that returns true if a term should be highlighted as a help term
	public init(contents: String, helpCallback: @escaping  HasHelpCallback) throws {
		(chunksSignal, chunksObserver) = Signal<[RmdChunk], Never>.pipe()
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
				// since markdown has no delimiter, parsedRange == innerRange
				let tchunk = MarkdownChunk(parser: parser, contents: parser.textStorage, range: parserChunk.innerRange)
				append(chunk: tchunk)
				lastTextChunk = tchunk
				lastWasInline = false
			case .code:
				let cchunk = CodeChunk(parser: parser, contents: parser.textStorage, range: parserChunk.innerRange, options: parserChunk.rOps)
				if parserChunk.isInline, let lastChunk = lastTextChunk {
					let achunk = InternalInlineCodeChunk(parser: parser, parserChunk: parserChunk, parentRange: lastChunk.range)
					attach(chunk: achunk, to: lastChunk.textStorage)
					lastChunk.append(inlineChunk: achunk, from: parser.textStorage)
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
					let dchunk = InternalInlineEquation(parser: parser, parserChunk: parserChunk, parentRange: lastChunk.range)
					lastChunk.append(inlineChunk: dchunk, from: parser.textStorage)
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

public protocol RmdChunk: class, CustomStringConvertible {
	var contents: NSAttributedString { get set }
	var chunkType: ChunkType { get }
	var rawText: String { get }
}

public protocol InlineChunk: RmdChunk {
	/// the range of the content in the parent chunk (excluding delimiters)
	var range: NSRange { get }
	/// the range of this chunk in the parent chunk (including delimiters)
	var chunkRange: NSRange { get }
	/// the range of this chunk in the document
	var documentRange: NSRange { get }
}

public protocol TextChunk: RmdChunk {
	/// inline code and equation chunks. Their text is still a part of this chunk
	var inlineElements: [InlineChunk] { get }
	/// the range of this chunk in the containing document
	var range: NSRange { get }
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

	public override var description: String { return "RmdChunk type \(chunkType) of length \(textStorage.length)" }
	
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
	private(set) var range: NSRange
	
	public override var description: String { return "\(super.description) with \(inlineElements.count) inline" }

	init(parser: SyntaxParser, contents: NSAttributedString, range: NSRange) {
		self.range = range
		// Use a fake chunk to create from contents.
		let pchunk = DocumentChunk(chunkType: .docs, docType: .rmd, equationType: .none,
								   range: range, innerRange: range, chunkNumber: 1)
		inlineElements = []
		super.init(parser: parser, chunk: pchunk)
		update(text: contents.attributedSubstring(from: range))
	}
	
	init(parser: SyntaxParser, contents: String, range: NSRange) {
		self.range = range
		// Use a fake chunk to create from contents.
		let pchunk = DocumentChunk(chunkType: .docs, docType: .rmd, equationType: .none,
								   range: range, innerRange: range, chunkNumber: 1)
		inlineElements = []
		super.init(parser: parser, chunk: pchunk)
		update(text: NSAttributedString(string: contents.substring(from: range)!))
		highlight(attributedString: textStorage, inRange: pchunk.innerRange)
	}
	
	func append(inlineChunk: InlineChunk, from fullText: NSTextStorage) {
		inlineElements.append(inlineChunk)
		// range doesn't include space after r code close `. where is it being added?
		let newRange = NSRange(location: range.location, length: inlineChunk.documentRange.upperBound - range.location)
		self.range = newRange
		update(text: fullText.attributedSubstring(from: self.range))
		highlight(attributedString: fullText, inRange: range)
	}

	override var rawText: String {
		return textStorage.string
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
		return "$$ \(textStorage.string.trimmingCharacters(in: .newlines)) $$\n"
	}
}

// MARK: -

class InternalInlineEquation: InternalRmdChunk, InlineChunk, Equation {
	var range: NSRange
	let documentRange: NSRange
	let chunkRange: NSRange
	
	init(parser: SyntaxParser, parserChunk: DocumentChunk, parentRange: NSRange) {
		range = NSRange(location: parserChunk.innerRange.location - parentRange.location, length: parserChunk.innerRange.length)
		documentRange = parserChunk.parsedRange
		chunkRange = NSRange(location: documentRange.location - parentRange.location, length: documentRange.length)
		let pchunk = DocumentChunk(chunkType: .equation, docType: .latex, equationType: .inline,
								   range: documentRange, innerRange: range, chunkNumber: 1)
		super.init(parser: parser, chunk: pchunk)
		update(text: parser.textStorage.attributedSubstring(from: documentRange))
	}
}

class InternalInlineCodeChunk: InternalRmdChunk, InlineChunk, Code {
	var range: NSRange
	let documentRange: NSRange
	let chunkRange: NSRange
	var options: MutableProperty<String>

	init(parser: SyntaxParser, parserChunk: DocumentChunk, parentRange: NSRange) {
		range = NSRange(location: parserChunk.innerRange.location - parentRange.location, length: parserChunk.innerRange.length)
		documentRange = parserChunk.parsedRange
		chunkRange = NSRange(location: documentRange.location - parentRange.location, length: documentRange.length)
		self.options = MutableProperty<String>(parserChunk.rOps)
		let pchunk = DocumentChunk(chunkType: .code, docType: .rmd, equationType: .none,
								   range: documentRange, innerRange: range, chunkNumber: 1)
		super.init(parser: parser, chunk: pchunk)
		update(text: parser.textStorage.attributedSubstring(from: documentRange))
	}
}

public extension String {
	/// surrounds self with startText and endText, only adding newlines if none already exist
	func surroundWithoutAddingNewlines(startText: String, endText: String) -> String {
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
