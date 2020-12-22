//
//  RmdDocument.swift
//  ClientCore
//
//  Created by Mark Lilback on 12/10/19.
//  Copyright © 2019 Rc2. All rights reserved.
//

import Cocoa
import Parsing
import Logging
import ReactiveSwift

// liikely don't need to do R highlighting here. Output is html, and editor uses without parrsing.
// editor needs to use without chunks

internal let parserLog = Logger(label: "io.rc2.rc2parser")

fileprivate extension Array {
	/// same as using subscript, but it does range checking and returns nil if invalid index
	func element(at index: Int) -> Element? {
		guard index >= 0, index < count else { return nil }
		return self[index]
	}
}

/// The parser uses a ChunkType, which inlcudes inline chunks. This type is for the types of chunks
/// that appear at the top level of a document (e.g. no inline)
public enum RootChunkType: String, Codable {
	case markdown, code, equation
	
	public init(_ pctype: ChunkType) {
		switch pctype {
		case .markdown:
			self = .markdown
		case .code:
			self = .code
		case .equation:
			self = .equation
		default:
			fatalError("unsupported chunk type \(pctype)")
		}
	}
}

public enum ParserError: Error {
	case parseFailed
	case invalidParser
}

extension Notification.Name {
	/// the object is the document that was updated. userInfo contains the the array of changed indexes with the key RmdDocument.changedIndexesKey
	public static let rmdDocumentUpdated = NSNotification.Name("rmdDocumentUpdated")
}

/// A parsed representation of an .Rmd file
public class RmdDocument: CustomDebugStringConvertible {
	/// used with the userInfo dictionary of a rmdDocumentUpdated notification
	public static let changedIndexesKey = "changedIndexes"
	
	/// Updates document with contents.
	/// If a code chunks changes and there are code chunks after it, the document will be completely refreshed.
	///
	/// - Parameter document: The document to update.
	/// - Parameter with: The updated content.
	///
	/// - Returns: If nil, consider the doucment completely refreshed. Otherwise, the indexes of chunks that just changed content.
	/// - Throws: any exception raised while creating a new document.
	public class func update(document: RmdDocument, with content: String) throws -> [Int]? {
		guard let parser = document.parser else { throw ParserError.invalidParser }
		guard document.attributedString.string != content else { return [] }
		let newDoc = try RmdDocument(contents: content, parser: parser)
		
		defer {
			document.chunks = newDoc.chunks
			// do the ones that trigger signals/notifications last
			document.frontMatter = newDoc.frontMatter
			document.textStorage.replace(with: newDoc.textStorage)
		}
		
		// if number of chunks changed, we can't list indexes that changed
		guard newDoc.chunks.count == document.chunks.count else { return nil }
		
		var changed = [Int]()
		let firstCodeIndex = document.chunks.firstIndex(where: { $0.chunkType == .code }) ?? -1
		for idx in 0..<newDoc.chunks.count {
			// compare if chunks are similar
			guard let oldChunk = document.chunks[idx] as? RmdDocChunk,
				let newChunk = newDoc.chunks[idx] as? RmdDocChunk,
				oldChunk != newChunk
				else { return nil }
			if newChunk.chunkType == .code && idx < firstCodeIndex { return nil }
			if newDoc.string(for: newChunk) != document.string(for: oldChunk) {
				changed.append(idx)
				document.chunks[idx] = newChunk
			}
		}
		NotificationCenter.default.post(name: .rmdDocumentUpdated, object: document, userInfo: [RmdDocument.changedIndexesKey: changed])
		return changed
	}
	
	private var textStorage = NSTextStorage()
	private weak var parser: Rc2RmdParser?
	/// the chunks in this document
	public private(set) var chunks = [RmdDocumentChunk]()
	/// any frontmatter that exists in the document
	public private(set) var frontMatter: String?
	/// the attributed contents of this document
	public var attributedString: NSAttributedString { return NSAttributedString(attributedString: textStorage) }
	/// version of contents after removing any text attachments
	public var rawString: String {
		return textStorage.string.replacingOccurrences(of: "\u{0ffe}", with: "")
	}
	
	public var debugDescription: String { return "RmdDocument with \(chunks.count) chunks" }
	
	/// types of ranges that can be requested
	public enum RangeType: Int {
		/// the contents without delimiters, arguments, etc.
		case inner
		/// the full contents of the chunk, including delimiters
		case outer
	}
	
	/// Creates a structure document.
	///
	/// - Parameters:
	///   - contents: Initial contents of the document.
	public init(contents: String, parser: Rc2RmdParser) throws {
		self.parser = parser
		textStorage.append(NSAttributedString(string: contents))
		let pchunks = try parser.parse(input: contents)
		for (idx, aChunk) in pchunks.enumerated() {
			chunks.append(RmdDocChunk(rawChunk: aChunk, number: idx, parentRange: aChunk.range))
		}
	}
	
	/// Get array of chunks that intersect with range
	/// - Parameters:
	///   - range: The range to check for
	///   - delta: The change in the range. Currently unused
	public func chunks(in range: NSRange, delta: Int = 0) -> [RmdDocumentChunk] {
		return chunks.compactMap {
			guard $0.parsedRange.contains(range.lowerBound) || $0.parsedRange.contains(range.upperBound) else { return nil }
			return $0
		}
	}
	
	/// Returns the contents of chunk as a String
	/// - Parameter chunk: The chunk whose ccntent will be returned
	/// - Parameter type: Which range should be used. Defaults to .outer
	/// - Returns: the requested contents
	public func string(for chunk: RmdDocumentChunk, type: RangeType = .outer) -> String {
		if chunk.isInline {
			guard let child = chunk as? RmdDocChunk else { fatalError("can't have inline without parent") }
			return textStorage.attributedSubstring(from: type == .outer ? child.parsedRange : child.innerRange).string
		}
		return attrString(for: chunk, rangeType: type).string.replacingOccurrences(of: "\u{0ffe}", with: "")
	}
	
	/// Returns the contents of chunk as an NSAttributedString
	/// - Parameter chunk: The chunk whose ccntent will be returned
	/// - Parameter type: Which range should be used. Defaults to .outer
	/// - Returns: the requested contents
	public func attrtibutedString(for chunk: RmdDocumentChunk, type: RangeType = .outer) -> NSAttributedString {
		return attrString(for: chunk, rangeType: .inner)
	}
	
	/// internal method to reduce code duplication of bounds checking
	private func attrString(for chunk: RmdDocumentChunk, rangeType: RangeType) -> NSAttributedString {
		guard let realChunk = chunk as? RmdDocChunk
			else { fatalError("invalid chunk index") }
		let desiredString = textStorage.attributedSubstring(from: rangeType == .outer ? realChunk.chunkRange : realChunk.innerRange)
		if chunk.isExecutable || chunk.isEquation {
			let baseStr = NSMutableAttributedString(attributedString: desiredString)
			do {
				if let parser = parser {
					let rng = NSRange(location: 0, length: baseStr.length)
					if chunk.isExecutable {
						let rhigh = try RHighlighter(baseStr, range: rng)
						try rhigh.start()
					} else if chunk.isEquation {
						parser.highlightEquation(contents: baseStr, range: rng)
					}
				}
			} catch {
				parserLog.info("error highligthing R code: \(error.localizedDescription)")
			}
			return baseStr
		}
		return desiredString
	}
}

extension RmdDocument: Equatable {
	public static func == (lhs: RmdDocument, rhs: RmdDocument) -> Bool {
		return lhs.textStorage == rhs.textStorage
	}
}

/// A chunk in a document
public protocol RmdDocumentChunk {
	/// the type of the chunk (.markdown, .code, .equation, including inline)
	var chunkType: ChunkType { get }
	/// true if a n inline code or equation chunk
	var isInline: Bool { get }
	/// trrue if it is a code module that can be executed
	var isExecutable: Bool { get }
	/// true if an equation or inline equation
	var isEquation: Bool { get }
	/// the range of this chunk in the document
	/// - Tag: parsedRange
	var parsedRange: NSRange { get }
	/// the range of this chunk in the document excluding delimiters e.q. (```, $$)
	var innerRange: NSRange { get }
	/// if isInline, the range of this chunk in its parent chunk. Otherwise, same as [parsedRange](x-source-tag://parsedRange)
	var chunkRange: NSRange { get }
	/// for .markdown chunks, any inline chunks. an empty arrary for other chunk types
	var children: [RmdDocumentChunk] { get }
}

internal class RmdDocChunk: RmdDocumentChunk {
	let chunkType: ChunkType
	let parserChunk: AnyChunk
	let chunkNumber: Int
	public private(set) var children = [RmdDocumentChunk]()
	
	init(rawChunk: AnyChunk, number: Int, parentRange: NSRange) {
		chunkType = rawChunk.type
		parserChunk = rawChunk
		chunkNumber = number
		parsedRange = rawChunk.range
		innerRange = rawChunk.innerRange
		if rawChunk.isInline {
			chunkRange = NSRange(location: parsedRange.location - parentRange.location,
								 length: parsedRange.length)
		} else {
			chunkRange = parsedRange
		}
		if let mchunk = rawChunk.asMarkdown {
			// need to add inline chunks
			var i = 0
			mchunk.inlineChunks.forEach { ichk in
				children.append(RmdDocChunk(rawChunk: ichk, number: i, parentRange: parsedRange))
				i += 1
			}
		}
		if rawChunk.type == .code {
			// FIXME: set name and argument
		}
	}
	
	/// true if this is a code or inline code chunk
	public var isExecutable: Bool { return chunkType == .code || parserChunk.type == .inlineCode }
	/// true if an equation or inline equation
	public var isEquation: Bool { return chunkType == .equation || parserChunk.type == .inlineEquation }
	/// trtue if this is an inline chunk
	public var isInline: Bool { return parserChunk.isInline }
	/// the range of this chunk in the entire document
	public let parsedRange: NSRange
	/// the range of the content (without open/close markers)
	public let innerRange: NSRange
	/// If an inline chunk, the range of this chunk inside the parent markdown chunk.
	/// Otherwise, the same a parsedRange
	public let chunkRange: NSRange
	// if this is a .code chunk, the argument in the chunk header
	public private(set) var arguments: String?
	// if this is a code chunk, the name given to the chunk
	public private(set) var name: String?
	
	public var executableCode: String {
		guard isExecutable else { return "" }
		if let cchunk = parserChunk.asCode { return cchunk.code }
		if let icc = parserChunk.asInlineCode { return icc.code }
		fatalError("not possible")
	}
}

extension RmdDocChunk: Equatable {
	static func == (lhs: RmdDocChunk, rhs: RmdDocChunk) -> Bool {
		return ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
	}
}
