//
//  DocumentChunk
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

public enum ChunkType {
	case documentation, rCode, equation
}

public enum EquationType: String {
	case NotAnEquation = "invalid", Inline = "inline", Display = "display", MathML = "MathML"
}

///Represents a "chunk" of data. An R document has 1 chunk.
/// Rmd and Rnw documents can have multiple chunks of different types.
open class DocumentChunk: NSObject {
	///A unique, serial number for each chunk.
	let chunkNumber: Int
	let name: String?
	///One of Documentation, RCode, or Equation
	let type: ChunkType
	
	var equationType: EquationType = .NotAnEquation
	var contentOffset: Int = 0
	//should only be used by the parser/highlighter
	internal(set) var parsedRange: NSRange = NSRange(location: 0, length: 0)
	
	/// is this chunk one of the types that are executable
	public var isExecutable: Bool { return type == .rCode }
	
	/// Returns the substring between the first and last newlines if this chunk is executable
	///
	/// - Parameter from: the string this chunk is a part of
	/// - Returns: the substring beteen first and last newlines
	public func executableCode(from: String) -> String {
		guard isExecutable else { return "" }
		guard let fullText = from.substring(from: parsedRange) else { return "" }
		//exclude character up to the first newline and before the last newline
		do {
			let regex = try NSRegularExpression(pattern: "(.*?\\n)(.*\\n)(.*\\n)")
			guard let result = regex.firstMatch(in: fullText, options: [], range: NSRange(location: 0, length: fullText.count)) else { return "" }
			guard let range = result.range(at: 2).toStringRange(fullText) else { return "" }
			return fullText.substring(with: range)
		} catch {
			return ""
		}
	}
	
	init(chunkType: ChunkType, chunkNumber: Int, name: String?=nil) {
		self.chunkNumber = chunkNumber
		self.type = chunkType
		self.name = name
		super.init()
	}
	
	convenience init(equationType: EquationType, chunkNumber: Int) {
		self.init(chunkType: .equation, chunkNumber:chunkNumber)
		self.equationType = equationType
	}
	
	//duplicates a chunk that differs only in chunkNumber
	func duplicateWithChunkNumber(_ newNum: Int) -> DocumentChunk {
		let dup = DocumentChunk(chunkType: type, chunkNumber: newNum, name: name)
		dup.parsedRange = parsedRange
		dup.contentOffset = contentOffset
		dup.equationType = equationType
		return dup
	}
	
	open override func isEqual(_ object: Any?) -> Bool {
		if let other = object as? DocumentChunk {
			return other.chunkNumber == chunkNumber && other.type == type && other.name == name && NSEqualRanges(parsedRange, other.parsedRange)
		}
		return false
	}
	
	open override var hash: Int {
		return chunkNumber.hashValue + type.hashValue + (name == nil ? 0 : name!.hashValue)
	}
	
	open override var description: String {
		let range = NSStringFromRange(parsedRange)
		switch self.type {
			case .rCode:
				return "R chunk \(chunkNumber) \"\((name == nil ? "" : name!))\" (\(range))"
			case .documentation:
				return "documentation chunk \(chunkNumber) (\(range))"
			case .equation:
				return "\(equationType.rawValue) equation chunk \(chunkNumber) (\(range))"
		}
	}
}
