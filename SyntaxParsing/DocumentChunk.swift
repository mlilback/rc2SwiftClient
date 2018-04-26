//
//  DocumentChunk
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

public let DocTypeKey = NSAttributedStringKey("DocTypeKey")
public let ChunkTypeKey = NSAttributedStringKey("ChunkTypeKey")
public let FragmentTypeKey = NSAttributedStringKey("FragmentTypeKey")
public let EquationTypeKey = NSAttributedStringKey("EquationTypeKey")

/// Possible types of equations
public enum DocType: String {
	case none, rmd, latex, r
}
/// Possible types of chunks
///
/// - docs: normal text (that might be interpreted as a markup language such as markdown)
/// - code: executable code (currently just R code)
/// - equation: a mathmatical equation
public enum ChunkType: String {
	case docs, code, equation
}

public enum FragmentType: String {
	case none, quote, comment, keyword, symbol, number
}

/// Possible types of equations
///
/// - none: not an equation type
/// - inline: an inline TeX equation
/// - display: a TeX equation (taking multiple lines)
/// - mathML: an equation specified in MathML
public enum EquationType: String {
	case none, inline, display, mathML = "MathML"
}

/// Protocol for any value that is a chunk
public protocol ChunkProtocol {
	var chunkType: ChunkType { get }
	var docType: DocType { get }
	var equationType: EquationType { get }
}

/// Represents a "chunk" of text. An R document has 1 chunk.
/// Rmd and Rnw documents can have multiple chunks of different types,
/// which are broken up into docs, code, and equations by parsing
/// various symbols (e.g. $$, ```, <...>).
public class DocumentChunk: ChunkProtocol {
	/// Type of chunk
	public let chunkType: ChunkType
	/// If the type is .equation, the type of the equation
	public let docType: DocType
	// The range of text this chunk contains
	public let equationType: EquationType
	/// If the type is .doc, the type of the doc
	public internal(set) var parsedRange: NSRange = NSRange(location: 0, length: 0)
	public internal(set) var innerRange: NSRange = NSRange(location: 0, length: 0)
	public var rOps: String = ""
	
	/// A unique, serial number for each chunk used in SessionEditorController's
	/// executePreviousChunks
	public let chunkNumber: Int
	/// An optional name for the chunk (normally only for code chunks)
	public let name: String?
	/// Is this chunk inline
	public let isInline: Bool
	/// Is this chunk one of the types that are executable?
	public var isExecutable: Bool { return chunkType == .code }
	
	/// TODO: the updated parser implementation should store this propery instead of using the executableCode() function
	/// public var executableRange: NSRange?
	/// Returns the substring between the first and last newlines if this chunk is executable
	///
	/// - Parameter from: the string this chunk is a part of
	/// - Returns: the substring beteen first and last newlines
	public func executableCode(from: String) -> String {
		guard isExecutable else { return "" }
		guard let str = from.substring(from: parsedRange) else { return "" }
		// Exclude character up to the first newline and before the last newline:
		do {
			let regex = try NSRegularExpression(pattern: "(.*?\\n)(.*\\n)(.*\\n)", options: .dotMatchesLineSeparators)
			guard let result = regex.firstMatch(in: str, options: [],
												range: NSRange(location: 0, length: str.count))
				else { return "" }
			guard let range = result.range(at: 2).toStringRange(str)
				else { return "" }
			return String(str[range])
		} catch {
			return ""
		}
	}
	
	init(chunkType: ChunkType, docType: DocType, equationType: EquationType,
		 range: NSRange,  innerRange: NSRange, chunkNumber: Int, name: String?=nil,
		 isInline: Bool = false) {
		self.chunkNumber = chunkNumber
		self.chunkType = chunkType
		self.docType = docType
		self.equationType = equationType
		self.name = name
		self.parsedRange = range
		self.innerRange = innerRange
		self.isInline = isInline
	}
	
	/// Returns a chunk that differs only in chunkNumber
	func duplicateWithChunkNumber(_ newNum: Int) -> DocumentChunk {
		return DocumentChunk(chunkType: chunkType, docType: docType, equationType: equationType,
							 range: parsedRange, innerRange: innerRange, chunkNumber: newNum, name: name)
	}
	
}

extension DocumentChunk: Equatable {
	public static func ==(lhs: DocumentChunk, rhs: DocumentChunk) -> Bool {
		return lhs.chunkNumber == rhs.chunkNumber && lhs.chunkType == rhs.chunkType
			&& lhs.docType == rhs.docType && lhs.equationType == rhs.equationType
			&& lhs.name == rhs.name && NSEqualRanges(lhs.parsedRange, rhs.parsedRange)
	}
}

extension DocumentChunk: Hashable {
	public var hashValue: Int { return ObjectIdentifier(self).hashValue }
}

extension DocumentChunk: CustomStringConvertible {
	public var description: String {
		let range = NSStringFromRange(parsedRange)
		switch self.chunkType {
		case .code:
			return "R code chunk \(chunkNumber) \"\(name ?? "")\" (\(range)) inline=\(isInline)"
		case .docs:
			return "Document chunk \(chunkNumber) (\(range))"
		case .equation:
			return "\(equationType.rawValue) equation chunk (LaTex)"
		}
	}
}

