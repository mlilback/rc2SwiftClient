//
//  StructruredDocument.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Model

public typealias ParserErrorHandler = (ParserError) -> Void

public let DocumentContentChanged = NSNotification.Name(rawValue: "StructuredDocumentContentChanged")

public class StructuredDocument: NSObject, NSTextStorageDelegate {
	/// the parsed chunks
	public var chunks: [DocumentChunk] { return parser.chunks }
	/// a single attributed string containing the contents of the document with syntax highlighting
	public let textStorage = NSTextStorage()
	
	private(set) public var parser: BaseSyntaxParser!
	public var contents: String { return textStorage.string }
	
	/// Error handler called if changes to the textStorage result in a parse error
	public var errorHandler: ParserErrorHandler?
	
	private var ignoreTextStorageNotifications: Bool = false
	private let notificationCenter: NotificationCenter
	
	/// create a structure document
	///
	/// - Parameters:
	///   - contents: initial contents of the document
	///   - notificationCenter: NotificationCenter to use, defaults to .default
	///   - errorHandler: closure called when a parser error happens from edits of the storage
	///   - helpCallback: callback that returns true if a term should be highlighted as a help term
	public init(contents: String, notificationCenter: NotificationCenter = .default, errorHandler: ParserErrorHandler? = nil, helpCallback: @escaping HighlighterHasHelpCallback)
	{
		self.notificationCenter = notificationCenter
		self.errorHandler = errorHandler
		textStorage.append(NSAttributedString(string: contents))
		parser = BaseSyntaxParser(storage: textStorage, fileType: FileType.fileType(withExtension: "Rmd")!, helpCallback: helpCallback)
	}
	
	/// Sets the content and triggers a restart
	///
	/// - Parameter contents: the new value for the contents
	/// - Throws: error if fails to parse
	public func set(contents: String) throws {
		textStorage.replaceCharacters(in: textStorage.string.fullNSRange, with: contents)
		try reparse()
		parser.colorChunks(parser.chunks)
	}
	
	/// Reparses the contents and updates the chunks
	///
	/// - Throws: error if fails to parse
	public func reparse() throws {
		guard parser.parse() else { throw ParserError.failedToParse }
	}

	// called when text editing has ended
	public func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int)
	{
		guard !ignoreTextStorageNotifications else { return }
		//we don't care if attributes changed
		guard editedMask.contains(.editedCharacters) else { return }
		//parse() return true if the chunks changed. in that case, we need to recolor all of them
		if parser.parse() {
			parser.colorChunks(parser.chunks)
		} else {
			//only color chunks in the edited range
			parser.colorChunks(parser.chunksForRange(editedRange))
		}
		notificationCenter.post(name: DocumentContentChanged, object: self)
	}
}
