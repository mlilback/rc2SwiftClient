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
import MJLLogger

class PreviewCodeHandler {
	enum Error: String, RawRepresentable, Swift.Error {
		case codeError
	}
	private struct ChunkInfo: Hashable {
		let chunkNumber: Int
		let type: ChunkType
		var currentHtml: String = ""
		var inlineHtml: [String] = []
	}
	
	var sessionController: SessionController
	let parsedDoc: MutableProperty<RmdDocument?>
	private var chunkInfo: [ChunkInfo?] = []
	
	init(sessionController: SessionController, docSignal: Signal<RmdDocument?, Never>) {
		self.sessionController = sessionController
		parsedDoc = MutableProperty<RmdDocument?>(nil)
		parsedDoc <~ docSignal
	}
	
	/// generates the html for all code chunks and any markdown chunks that contain inline code
	// TODO: this needs to return a SignalHandler so the code can be executed async
	func cacheCode(changedChunks: inout [Int], in document: RmdDocument) {
		// if not the same size as last time, then all code is dirty
		if document.chunks.count != chunkInfo.count {
			chunkInfo = Array<ChunkInfo?>(repeating: nil, count: document.chunks.count)
		}
		// generate html for each chunk.
		for (chunkNumber, chunk) in document.chunks.enumerated() {
			if chunk.chunkType == .markdown, chunk.children.count > 0 {
				// need to generate inline html
				var inline = [String]()
				for (inlineIndex, inlineChunk) in chunk.children.enumerated() {
					inline[inlineIndex] = inlineHtmlFor(chunk: inlineChunk, parent: chunk)
				}
				chunkInfo[chunkNumber] = ChunkInfo(chunkNumber: chunkNumber, type:.markdown, inlineHtml: inline)
				break // exit this loop
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
	
	private func inlineHtmlFor(chunk: RmdDocumentChunk, parent: RmdDocumentChunk) -> String {
		precondition(parsedDoc.value != nil)
		// just return nothing if not code
		guard chunk.isInline else { return "" }
		// TODO: generate actual code
		return parsedDoc.value!.string(for: chunk, type: .outer)
//		return  parent.contents.string.substring(from: chunk.chunkRange) ?? "<span class=\"internalError\">invalid inline data</span>"
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
