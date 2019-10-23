//
//  RmdDocument.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Model
import MJLLogger
import ReactiveSwift

/// Errors that can be thrown while working with SyntaxParsing.
public enum ParserError: Error {
	/// an inline equation was found outside a text chunk. This should not be possible
	case inlineEquationNotInTextChunk
}

public typealias HasHelpCallback = (String) -> Bool

/// A document that represents a parsed Rmd document.
public class RmdDocument: CustomDebugStringConvertible {
	/// Chunks comprising this document.
	public private(set) var chunks: [RmdChunk] = []
	/// Text included at the top of the document in FrontMatter format..
	public let frontMatter = MutableProperty("")

	private var textStorage = NSTextStorage()
	private var parser: SyntaxParser
	
	public var debugDescription: String { return "RmdDocument with \(chunks.count) chunks" }
	
	/// Updates document with contents.
	/// If a code chunks changes and there are code chunks after it, the document will be completely refreshed.
	///
	/// - Parameter document: The document to update.
	/// - Parameter with: The updated content.
	///
	/// - Returns: If nil, consider the doucment completely refreshed. Otherwise, the indexes of chunks that just changed content.
	/// - Throws: any exception raised while creating a new document.
	public class func update(document: RmdDocument, with content: String) throws -> [Int]? {
		let helpCallback = document.parser.helpCallback
		let newDoc = try RmdDocument(contents: content, helpCallback: helpCallback)

		defer {
			document.chunks = newDoc.chunks
			document.parser = newDoc.parser
			// do the ones that trigger signals/notifications last
			document.frontMatter.value = newDoc.frontMatter.value
			document.textStorage.replace(with: newDoc.textStorage)
		}
		
		// if number of chunks changed, we can't list indexes that changed
		guard newDoc.chunks.count == document.chunks.count else { return nil }

		var changed = [Int]()
		let firstCodeIndex = document.chunks.firstIndex(where: {$0.chunkType == .code}) ?? -1
		for idx in 0..<newDoc.chunks.count {
			// compare if chunks are similar
			guard let oldChunk = document.chunks[idx] as? InternalRmdChunk,
				let newChunk = newDoc.chunks[idx] as? InternalRmdChunk,
				oldChunk.matchesForUpdate(chunk: newChunk)
			else { return nil }
			if newChunk.chunkType == .code && idx < firstCodeIndex { return nil }
			if newChunk.rawText != oldChunk.rawText {
				changed.append(idx)
				document.chunks[idx] = newChunk
			}
		}
		return changed
	}
	
	/// Creates a structure document.
	///
	/// - Parameters:
	///   - contents: Initial contents of the document.
	///   - helpCallback: Callback that returns true if a term should be highlighted as a help term.
	public init(contents: String, helpCallback: HasHelpCallback? = nil) throws {
		textStorage.append(NSAttributedString(string: contents))
		let filetype = FileType.fileType(withExtension: "Rmd")!
		parser = SyntaxParser(storage: textStorage, fileType: filetype, helpCallback: helpCallback)
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
				chunks.append(tchunk)
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
				chunks.append(cchunk)
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
					chunks.append(dchunk)
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
		// FIXME: MASSIVE CODE SMELL. Shouln not need this test, but the image code crashes during unit tests
		if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
			let image = chunk is Equation ? NSImage(named: "inlineEquation") : NSImage(named: NSImage.advancedName)
			let acell = InlineAttachmentCell(imageCell: image)
			attach.bounds = CGRect(origin: CGPoint(x: 0, y: -5), size: acell.image!.size)
			attach.attachmentCell = acell
		}
		storage.append(NSAttributedString(attachment: attach))
	}
}

// MARK: - protocols

/// Marker protocol to denote equations.
public protocol Equation: class {}

/// Adds properties required for Code chunks.
public protocol Code: class {
	var options: MutableProperty<String> { get }
}

/// A base chunk of a document.
public protocol RmdChunk: class, CustomStringConvertible {
	/// The attributed textual contents of the chunk.
	var contents: NSAttributedString { get set }
	/// The type of chunk this is.
	var chunkType: ChunkType { get }
	/// The raw text version of this.
	/// - Warning: Should always be used over contents.string. It removes certain hidden characters (attachment placeholders) that will mess up string comparisons.
	var rawText: String { get }
}

/// A chunk that is embedded inside a TextChunk.
public protocol InlineChunk: RmdChunk {
	/// The range of the content in the parent chunk (excluding delimiters).
	var range: NSRange { get }
	/// The range of this chunk in the parent chunk (including delimiters).
	var chunkRange: NSRange { get }
	/// The range of this chunk in the document.
	var documentRange: NSRange { get }
}

/// A textual chunk that normally contains Markdown.
public protocol TextChunk: RmdChunk {
	/// Inline code and equation chunks. Their text is still a part of this chunk.
	var inlineElements: [InlineChunk] { get }
	/// The range of this chunk in the containing document.
	var range: NSRange { get }
}

public typealias InlineEquationChunk = InlineChunk & Equation
public typealias InlineCodeChunk = InlineChunk & Code

// MARK: - attachments
/// NSTextAttachment subclass to hold inline code and equations.
public class InlineAttachment: NSTextAttachment {
	/// The inline chunk contained in this attachment.
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
	
	// remove any text attachments from the string
	var rawText: String {
		return textStorage.string.replacingOccurrences(of: "\u{0ffe}", with: "")
	}

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
	
	// subclasses should override if they need to consider other factors
	func matchesForUpdate(chunk: InternalRmdChunk) -> Bool {
		guard type(of: self) == type(of: chunk), self.chunkType == chunk.chunkType,
			self.docType == chunk.docType, self.equationType == chunk.equationType
			else { return false }
		return true
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
		// remove any attachment characters
		let ss = "\u{ef}"
		var str = textStorage.string.replacingOccurrences(of: ss, with: "")
		str = textStorage.string.replacingOccurrences(of: "\u{fffc}", with: "")
		return str
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
		let chunkText = parser.textStorage.attributedSubstring(from: documentRange)
		update(text: chunkText)
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
