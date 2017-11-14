//
//  DocumentChunk
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

/// Possible types of chunks
///
/// - documentation: normal text (that might be interpreted as a markup language such as markdown)
/// - rCode: executable code
/// - equation: a mathmatical equation
public enum ChunkType {
	case documentation, executable, equation
}

/// The possible types of equations
///
/// - invalid: An invalid equation
/// - inline: An inline TeX equation
/// - display: A TeX equation
/// - mathML: An equation specified in MathML
public enum EquationType: String {
	case invalid, inline, display, mathML = "MathML"
}

/// Represents a "chunk" of data. An R document has 1 chunk.
/// Rmd and Rnw documents can have multiple chunks of different types.
public class DocumentChunk {
	/// A unique, serial number for each chunk.
	public let chunkNumber: Int
	/// An optional name for the chunk (normally only for code chunks)
	public let name: String?
	/// the type of chunk
	public let type: ChunkType

	/// if the type is .equation, the type of the equation
	var equationType: EquationType = .invalid

	// var contentOffset: Int = 0

	// The range of text this chunk contains
	public internal(set) var parsedRange: NSRange = NSRange(location: 0, length: 0)
	
	/// is this chunk one of the types that are executable
	public var isExecutable: Bool { return type == .executable }
	
	/// TODO: the updated parser implementation should store this propery instead of using the executableCode() function
	/// public var executableRange: NSRange?
	
	/// Returns the substring between the first and last newlines if this chunk is executable
	///
	/// - Parameter from: the string this chunk is a part of
	/// - Returns: the substring beteen first and last newlines
	public func executableCode(from: String) -> String {
		guard isExecutable else { return "" }
		guard let fullText = from.substring(from: parsedRange) else { return "" }
		//exclude character up to the first newline and before the last newline
		do {
			let regex = try NSRegularExpression(pattern: "(.*?\\n)(.*\\n)(.*\\n)", options: .dotMatchesLineSeparators)
			guard let result = regex.firstMatch(in: fullText, options: [], range: NSRange(location: 0, length: fullText.count)) else { return "" }
			guard let range = result.range(at: 2).toStringRange(fullText) else { return "" }
			return String(fullText[range])
		} catch {
			return ""
		}
	}
	
	init(chunkType: ChunkType, chunkNumber: Int, name: String?=nil) {
		self.chunkNumber = chunkNumber
		self.type = chunkType
		self.name = name
	}
	
	convenience init(equationType: EquationType, chunkNumber: Int) {
		self.init(chunkType: .equation, chunkNumber:chunkNumber)
		self.equationType = equationType
	}
	
	/// returns a chunk that differs only in chunkNumber
	func duplicateWithChunkNumber(_ newNum: Int) -> DocumentChunk {
		let dup = DocumentChunk(chunkType: type, chunkNumber: newNum, name: name)
		dup.parsedRange = parsedRange
		dup.equationType = equationType
		return dup
	}
}

extension DocumentChunk: Equatable {
	public static func ==(lhs: DocumentChunk, rhs: DocumentChunk) -> Bool {
		return lhs.chunkNumber == rhs.chunkNumber && lhs.type == rhs.type && lhs.name == rhs.name && NSEqualRanges(lhs.parsedRange, rhs.parsedRange)
	}
}

extension DocumentChunk: Hashable {
	public var hashValue: Int { return ObjectIdentifier(self).hashValue }
}

extension DocumentChunk: CustomStringConvertible {
	public var description: String {
		let range = NSStringFromRange(parsedRange)
		switch self.type {
		case .executable:
			return "R chunk \(chunkNumber) \"\(name ?? "")\" (\(range))"
		case .documentation:
			return "documentation chunk \(chunkNumber) (\(range))"
		case .equation:
			return "\(equationType.rawValue) equation chunk \(chunkNumber) (\(range))"
		}
	}
}
