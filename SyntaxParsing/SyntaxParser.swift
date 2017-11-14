//
//  SyntaxParser
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import os
import ClientCore
import Model

extension OSLog {
	/// Log to use for syntax parsing messages
	static let syntax = OSLog(subsystem: AppInfo.bundleIdentifier, category: "parser")
}

/// Protocol for an object that parses the contents of an NSTextStorage into an array of DocumentChunk objects
public protocol SyntaxParser: class {
	/// The text storage that is parsed
	var textStorage: NSTextStorage { get }
	/// The type of file parsed by this parser
	var fileType: FileType { get }
	/// The current array of parsed chunks
	var chunks: [DocumentChunk] { get }
	/// The current array of parsed chunks which are executable
	var executableChunks: [DocumentChunk] { get }
	
	/// Returns the index of the first chunk containing the start of the range
	///
	/// - Parameter range: The range whose start index should be found
	/// - Returns: the index of the chunk containing the start of the range
	func indexOfChunk(range: NSRange) -> Int
	
	/// Returns ordered array of chunks that contain the text in the requested range
	///
	/// - Parameter range: The range of text to find chunks for
	/// - Returns: The chunks that contain text in the specified range
	func chunksForRange(_ range: NSRange) -> [DocumentChunk]
	
	/// Parses the text storage and updates the chunks array
	///
	/// - Returns: true if the chunks array was updated
	func parse() -> Bool
	
	/// Updates the NSTextStorage attributes for color and backgroundColor
	///
	/// - Parameter chunksToColor: array of chunks to color
	func colorChunks(_ chunksToColor: [DocumentChunk])
}

