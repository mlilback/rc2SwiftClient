//
//  SessionState.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Model
import Rc2Common

public struct SessionState: Codable {
	public var outputState: OutputControllerState
	public var editorState: EditorState
	public var imageCacheState: ImageCacheState
	
	/// default initializer
	public init() {
		outputState = OutputControllerState()
		editorState = EditorState()
		imageCacheState = ImageCacheState()
	}
	
	/// initializes via decoding serialized data
	/// - Parameter from: The serialized data
	/// - Throws: any error from the decoder
	public init(from data: Data) throws {
		let parser = JSONDecoder()
		parser.dateDecodingStrategy = .secondsSince1970
		let restoredState = try parser.decode(SessionState.self, from: data)
		outputState = restoredState.outputState
		editorState = restoredState.editorState
		imageCacheState = restoredState.imageCacheState
	}
	
	/// serializes self
	/// - Returns: serialized data
	/// - Throws: any error from the encoder
	public func serialize() throws -> Data {
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .secondsSince1970
		return try encoder.encode(self)
	}
	
	public struct OutputControllerState: Codable {
		public var selectedTabId: Int = 0
		public var selectedImageId: Int = 0
		public var commandHistory: [String] = []
		public var resultsContent: Data?
		public var webViewState = WebViewState()
		public var helpViewState = WebViewState()
	}
	
	public struct EditorState: Codable {
		public var editorFontDescriptor: Data?
		public var lastSelectedFileId: Int = -1
	}
	
	public struct ImageCacheState: Codable {
		public var hostIdentifier: String = ""
		public var images: [SessionImage] = []
	}
	
	public struct WebViewState: Codable {
		public var contentsId: Int?
	}
}
