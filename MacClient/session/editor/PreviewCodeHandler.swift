//
//  PreviewCodeHandler.swift
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

class PreviewCodeHandler {
	enum Error: String, RawRepresentable, Swift.Error {
		case codeError
	}
	private struct ChunkInfo: Hashable {
		let chunkNumber: Int
		let type: RootChunkType
		var currentHtml: String = ""
		var inlineHtml: [String] = []
	}
	
	var session: Session
//	let parsedDoc: MutableProperty<RmdDocument?>
	private var chunkInfo: [ChunkInfo?] = []
	public var contentCached: Bool { return chunkInfo.count > 0 }
	
	init(session: Session, docSignal: Signal<RmdDocument?, Never>) {
		self.session = session
//		parsedDoc = MutableProperty<RmdDocument?>(nil)
//		parsedDoc <~ docSignal
//		parsedDoc.signal.observeValues { [weak self] (doc) in
//			guard let me = self else { return }
//			guard let theDoc = doc else { me.chunkInfo.removeAll(); return }
//			guard !me.contentCached else { return }
//			var indexes = [Int](0..<theDoc.chunks.count)
//			me.cacheCode(changedChunks: &indexes, in: theDoc)
//		}
	}
	/// caches the html for all code chunks and any markdown chunks that contain inline code
	/// - Parameter document: the document to cache
	func cacheAllCode(in document: RmdDocument) {
		var changedChunkIndexes = [Int](0..<document.chunks.count)
		cacheCode(changedChunks: &changedChunkIndexes, in: document)
	}
	
	/// caches the html for all code chunks and any markdown chunks that contain inline code
	// TODO: this needs to return a SignalHandler so the code can be executed async
	/// - Parameter changedChunks: array of chunkNumbers that caller thinks changed.
	///  Any chunk where the output did not change is removed. Ones not included where the output did change are added.
	/// - Parameter document: the document to cache
	func cacheCode(changedChunks: inout [Int], in document: RmdDocument) {
		// if not the same size as last time, then all code is dirty
		if document.chunks.count != chunkInfo.count {
			chunkInfo = [ChunkInfo?]()
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
				chunkInfo[chunkNumber]?.inlineHtml = inline
				continue
			}
			guard chunk.chunkType == .code else { continue }
			let currentHtml = htmlForChunk(number: chunkNumber)
			if chunkInfo[chunkNumber]?.currentHtml == currentHtml,
				let changedIndex = changedChunks.firstIndex(where: { $0 == chunkNumber }) {
				changedChunks.remove(at: changedIndex)
			}
			if !changedChunks.contains(chunkNumber) {
				changedChunks.append(chunkNumber)
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
	func htmlForChunk(number: Int) -> String {
		precondition(number < chunkInfo.count)
		guard let chunkInfo = chunkInfo[number] else { fatalError("invalid chunk number") }
		return chunkInfo.currentHtml
	}
	
	/// returns the HTML for an inline chunk in  a markdown chunk
	func inlineEquationHtml(chunkNumber: Int, inlineIndex: Int) -> String {
		precondition(chunkNumber < chunkInfo.count)
		guard let chunkInfo = chunkInfo[chunkNumber] else { fatalError("invalid chunk number") }
		let chunkChildren = chunkInfo.inlineHtml
		precondition(inlineIndex < chunkInfo.inlineHtml.count, "invalid inline index")
		return chunkChildren[inlineIndex]
	}
	
	private func htmlFor(chunkNumber: Int, inlineIndex: Int) -> String {
		guard let chunkInfo = chunkInfo[chunkNumber], chunkInfo.inlineHtml.count > inlineIndex
		else {
			Log.error("invalid chunk indexes")
			assertionFailure("invalid indexes")
			return ""
		}
		return chunkInfo.inlineHtml[inlineIndex]
	}
}
