//
//  PreviewChunkCache.swift
//  MacClient
//
//  Created by Mark Lilback on 10/13/19.
//  Copyright © 2019 Rc2. All rights reserved.
//

import Foundation
import ReactiveSwift
import ClientCore
import Networking
import MJLLogger

// siftlint:disable cyclomatic_complexity

public class PreviewChunkCache {
	public enum Error: String, RawRepresentable, Swift.Error {
		case codeError
	}
	private struct ChunkInfo: Hashable, Codable {
		let chunkNumber: Int
		let type: RootChunkType
		var currentHtml: String = ""
		var inlineHtml: [String] = []
	}

	private struct SavedCache: Codable {
		let fileId: Int
		let fileVersion: Int
		let chunks: [ChunkInfo]
	}
		
	let previewId: Int
	let fileId: Int
	let workspace: AppWorkspace
	private var chunkInfo: [ChunkInfo] = []
	public var contentCached: Bool { return chunkInfo.count > 0 }
	public let _document: Property<RmdDocument?>
	private var document: RmdDocument {
		guard let doc = _document.value else { fatalError("previewChunk asked to use nil document") }
		return doc
	}

	public init(previewId: Int, fileId: Int, workspace: AppWorkspace, documentProperty: Property<RmdDocument?>) {
		self.previewId = previewId
		self.fileId = fileId
		self.workspace = workspace
		self._document = Property<RmdDocument?>(documentProperty)
		NotificationCenter.default.addObserver(self, selector: #selector(documentUpdated), name: .rmdDocumentUpdated, object: self.document)
	}

	/// called when the document's content was updated
	@objc func documentUpdated(note: Notification) {
		guard var changedIndexes = note.userInfo?[RmdDocument.changedIndexesKey] as? [Int] else {
			Log.warn("received documentUpdated notification without changedIndexes", .app)
			return
		}
		cacheCode(changedChunks: &changedIndexes)
	}
	
	/// Clears the code chache, should be called when the document has changed
	public func clearCache() {
		chunkInfo.removeAll()
	}

	/// caches the html for all code chunks and any markdown chunks that contain inline code
	/// - Parameter document: the document to cache
	public func cacheAllCode() {
		var changedChunkIndexes = [Int](0..<document.chunks.count)
		cacheCode(changedChunks: &changedChunkIndexes)
	}

	/// caches the html for all code chunks and any markdown chunks that contain inline code
	// TODO: this needs to return a SignalHandler so the code can be executed async
	/// - Parameter changedChunks: array of chunkNumbers that caller thinks changed.
	///  Any chunk where the output did not change is removed. Ones not included where the output did change are added.
	/// - Parameter document: the document to cache
	// swiftlint:disable:next cyclomatic_complexity
	public func cacheCode(changedChunks: inout [Int]) {
		// if not the same size as last time, then all code is dirty
		if document.chunks.count != chunkInfo.count {
			chunkInfo = [ChunkInfo]()
			for i in 0..<document.chunks.count {
				chunkInfo.append(ChunkInfo(chunkNumber: i, type: RootChunkType(document.chunks[i].chunkType)))
			}
		}
		// generate html for each chunk.
		for (chunkNumber, chunk) in document.chunks.enumerated() {
			if chunk.chunkType == .markdown, chunk.children.count > 0 {
				// need to generate inline html
				var inline = [String]()
				for inlineChunk in chunk.children {
					inline.append(inlineHtmlFor(chunk: inlineChunk, parent: chunk, document: document))
				}
				guard chunkInfo[chunkNumber].inlineHtml != inline else { continue }
				chunkInfo[chunkNumber].inlineHtml = inline
				if !changedChunks.contains(chunkNumber) {
					changedChunks.append(chunkNumber)
				}
				continue
			}
			guard chunk.chunkType == .code else { continue }
			let currentHtml = htmlForChunk(document: document, number: chunkNumber)
			if chunkInfo[chunkNumber].currentHtml != currentHtml {
				if let changedIndex = changedChunks.firstIndex(where: { $0 == chunkNumber }) {
					changedChunks.remove(at: changedIndex)
				}
				if !changedChunks.contains(chunkNumber) {
					changedChunks.append(chunkNumber)
				}
			}
		}
		changedChunks.sort()
	}

	private func inlineHtmlFor(chunk: RmdDocumentChunk, parent: RmdDocumentChunk, document: RmdDocument) -> String {
		// just return nothing if not code
		guard chunk.isInline else { return "" }
		// TODO: generate actual code
		let parHTML = document.string(for: chunk, type: .outer)
		return parHTML
	}

	/// returns the html for the specified chunk.
	public func htmlForChunk(document: RmdDocument, number: Int) -> String {
		let src = document.string(for: document.chunks[number], type: .inner)
		let output: String
		if chunkInfo[number].currentHtml.count > 0 {
			output = chunkInfo[number].currentHtml
		} else {
			// TODO: this should give user notice that chunk needs to be executed
			output = "<!-- R output will go here -->"
		}
		return """
		<div class="codeChunk">
		<div class="codeSource">
		\(src.addingUnicodeEntities.replacingOccurrences(of: "\n", with: "<br>\n"))
		</div><div class="codeOutput">
		\(output)
		</div>
		</div>
		"""
	}

	/// returns the HTML for an inline chunk in  a markdown chunk
	func inlineEquationHtml(chunkNumber: Int, inlineIndex: Int) -> String {
		guard let chunkInfo = chunkInfo[safe: inlineIndex] else { fatalError("invalid chunk number") }
		let chunkChildren = chunkInfo.inlineHtml
		precondition(inlineIndex < chunkInfo.inlineHtml.count, "invalid inline index")
		return chunkChildren[inlineIndex]
	}

	private func htmlFor(chunkNumber: Int, inlineIndex: Int) -> String {
		guard let chunkInfo = chunkInfo[safe: chunkNumber], chunkInfo.inlineHtml.count > inlineIndex
		else {
			Log.error("invalid chunk indexes")
			assertionFailure("invalid indexes")
			return ""
		}
		return chunkInfo.inlineHtml[inlineIndex]
	}
}

extension PreviewChunkCache {
	func saveCache() {
	}
}
