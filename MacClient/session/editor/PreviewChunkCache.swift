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
import GRDB

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
		var output: String = ""
		var outputIsValid: Bool = false
	}

	private struct SavedCacheEntry: Codable, FetchableRecord, TableRecord, PersistableRecord {
		static var databaseTableName: String = "cacheEntry"
		let fileId: Int
		let fileVersion: Int
		let chunks: [ChunkInfo]
	}
		
	let previewId: Int
	let fileId: Int
	let workspace: AppWorkspace
	private var dbQueue: DatabaseQueue?
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
		NotificationCenter.default.addObserver(self, selector: #selector(appTerminating(note:)), name: NSApplication.willTerminateNotification, object: nil)
		readCache()
	}
	
	deinit {
		saveCache()
	}
	
	/// notification handler for app termination. Saves database before exiting
	@objc func appTerminating(note: Notification?) {
		saveCache()
		dbQueue = nil
	}
	
	/// called when the document's content was updated
	@objc func documentUpdated(note: Notification) {
		guard var changedIndexes = note.userInfo?[RmdDocument.changedIndexesKey] as? [Int] else {
			Log.warn("received documentUpdated notification without changedIndexes", .app)
			return
		}
		cacheCode(changedChunks: &changedIndexes)
	}
	
	/// if specified chunk is a code chunk, stores the code output for that chunk. recaches the code so no need to do that affter this call
	public func updateCodeOutput(chunkNumber: Int, outputContent: String) {
		guard let chunk = chunkInfo[safe: chunkNumber], chunk.type == .code else {
			Log.warn("invali chunk index", .app)
			return
		}
		Log.info("updating output for chunk \(chunkNumber)")
		chunkInfo[chunkNumber].output = outputContent
		chunkInfo[chunkNumber].outputIsValid = true
		// recache output
		var changed = [chunkNumber]
		cacheCode(changedChunks: &changed)
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
					inline.append(inlineHtmlFor(chunk: inlineChunk, parent: chunk))
				}
				guard chunkInfo[chunkNumber].inlineHtml != inline else { continue }
				chunkInfo[chunkNumber].inlineHtml = inline
				if !changedChunks.contains(chunkNumber) {
					changedChunks.append(chunkNumber)
				}
				continue
			}
			guard chunk.chunkType == .code else {
				// TODO: need to track inline code chunks, or markdown chunks with inline code
				chunkInfo[chunkNumber].outputIsValid = true
				continue
			}
			let currentHtml = htmlForChunk(chunkNumber: chunkNumber)
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
	
	/// Called to notify a chunk will be execute. Invalidates the output of all code chunks that foillow
	/// - Parameter chunkIndex: the chunkIndex
	public func willExecuteChunk(chunkIndex: Int) {
		precondition(chunkInfo.indices.contains(chunkIndex))
		// invalidate all future code chunks
		for idx in chunkIndex...chunkInfo.count where chunkInfo[idx].type == .code {
			chunkInfo[idx].outputIsValid = false
		}

	}
	
	/// Reports if the specified's output is valid and doesn't need updating
	/// - Parameter number: the chunk number
	/// - Returns: true if the otuput is known to be valid
	public func isChunkOutputValid(chunkIndex: Int) -> Bool {
		chunkInfo[chunkIndex].outputIsValid
	}
	
	private func inlineHtmlFor(chunk: RmdDocumentChunk, parent: RmdDocumentChunk) -> String {
		// just return nothing if not code
		guard chunk.isInline else { return "" }
		guard chunk.chunkType == .inlineCode else {
			// for inline equations, just return the source
			return document.string(for: chunk)
		}
		// TODO: generate actual code. need to be able to tell what context to use
		let parHTML = document.string(for: chunk, type: .outer)
		return parHTML
	}

	/// returns the html for the specified chunk.
	public func htmlForChunk(chunkNumber: Int) -> String {
		let src = document.string(for: document.chunks[chunkNumber], type: .inner)
		let output: String
		if chunkInfo[chunkNumber].output.count > 0 {
			output = chunkInfo[chunkNumber].output
		} else {
			// TODO: this should give user notice that chunk needs to be executed
			output = "<!-- R output will go here -->"
		}
		return """
		<div class="codeChunk">
		<div class="codeSource">
		\(src.trimmingCharacters(in: .whitespacesAndNewlines).addingUnicodeEntities.replacingOccurrences(of: "\n", with: "<br>\n"))
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
	var cacheTableName: String { "cacheEntry" }
	private func cacheURL() -> URL {
		let fm = FileManager()
		do {
			let appSupport = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
			return appSupport.appendingPathComponent(Bundle.main.bundleIdentifier!, isDirectory: true).appendingPathComponent("previewCache.sqlite")
		} catch {
			fatalError("error looking for app support directory: \(error)")
		}
	}
	
	func readCache() {
		if dbQueue == nil { initializeCache() }
		do {
			try dbQueue!.read { db in
				do {
					if let oldRec = try SavedCacheEntry.fetchOne(db, sql: "select * FROM \(cacheTableName) where fileID = \(fileId)")
					{
						self.chunkInfo = oldRec.chunks
					}
				} catch {
					Log.warn("error reading cache: \(error)", .app)
					throw error
				}
			}
		} catch {
				Log.warn("error reading cache: \(error)", .app)
		}
	}
	
	@objc func saveCache() {
		if dbQueue == nil { initializeCache() }
		let toSave = SavedCacheEntry(fileId: fileId, fileVersion: workspace.file(withId: fileId)!.version, chunks: chunkInfo)
		do {
			try dbQueue!.write { db in
				try db.execute(sql: "delete from \(cacheTableName) where fileId = \(fileId)")
				if try SavedCacheEntry.fetchOne(db, key: fileId) == nil  {
					try  toSave.insert(db)
				} else {
					try toSave.update(db)
				}
			}
		} catch {
			Log.warn("failed to save cache: \(error)", .app)
		}
	}
	
	private func initializeCache() {
		do {
			var config = Configuration()
			config.foreignKeysEnabled = true
			config.readonly = false
			dbQueue = try DatabaseQueue(path: cacheURL().path)
			try dbQueue?.write { db in
				//create table if it doesn't exist
				try db.create(table: cacheTableName, ifNotExists: true) { t in
					t.column("fileId", .integer).primaryKey()
					t.column("fileVersion", .integer)
					t.column("chunks", .blob)
				}
			}
		} catch {
			Log.warn("error creating preview cache \(error)", .app)
			return
		}
	}
}
