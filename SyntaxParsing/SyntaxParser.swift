//
//  SyntaxParser
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
#if os(OSX)
	import AppKit
#endif
import Model

//public let rc2syntaxAttributeKey = NSAttributedStringKey("rc2AttributeKey")
//
//public enum SyntaxAttributeType: String {
//	case none, frontmatter, code, codeOptions, document, equation, mathML, quote, comment, keyword, symbol, number, block, inline
//}

/// Protocol for an object that parses the contents of an NSTextStorage
/// into an array of DocumentChunk objects, used externally instead of
/// particular parser objects.
public protocol SyntaxParser: class {
	/// Text storage that is parsed
	var textStorage: NSTextStorage { get }
	/// File type parsed, used to determine highlighter(s) to use
	var fileType: FileType { get }
	/// Current array of parsed chunks
	var chunks: [DocumentChunk] { get }
	
	// MARK: - External use only (mainly SessionEditorController):
	
	/// Current array of parsed chunks that are executable
	var executableChunks: [DocumentChunk] { get }
	
	/// Calls subclasses to parse if textStorage has changed.
	/// - Returns: true if the chunks array was updated
	@discardableResult
	func parse() -> Bool
	
	func parseAndAttribute(string: NSMutableAttributedString, docType: DocType,
						   inRange: NSRange, makeChunks: Bool)

	/// Returns the index of the first chunk containing the start of the range.
	/// Used in: SessionEditorController: NSTextViewDelegate & NSTextStorageDelegate.
	///
	/// - Parameter range: The range whose start index should be found.
	/// - Returns: the index of the chunk containing the start of the range,
	///   or 0 if not found.
	func indexOfChunk(inRange: NSRange) -> Int
	
	/// Returns ordered array of chunks that contain the text in the requested range.
	/// Used in: indexOfChunk and SessionEditorController: NSTextStorageDelegate.
	///
	/// - Parameter range: the range of text to find chunks for.
	/// - Returns: the chunks that contain text in the specified range.
	func chunksForRange(_ range: NSRange) -> [DocumentChunk]
	
	/// Updates the NSTextStorage attributes with color and back backgroundColor
	/// based on coloring highlighted, parsed text.
	///
	/// - Parameter chunksToColor: array of chunks to color
	func colorChunks(_ chunksToColor: [DocumentChunk])
}

