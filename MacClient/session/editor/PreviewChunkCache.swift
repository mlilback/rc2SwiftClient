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
	/// owner is responsible for updating this anytime the document is updated.
	var document: RmdDocument?

	private let mdownParser = MarkdownParser()
	// regular expressions
	private var lineContiuationRegex: NSRegularExpression
	private var openDoubleDollarRegex: NSRegularExpression
	private var closeDoubleDollarRegex: NSRegularExpression
	private let dataSourceRegex: NSRegularExpression = {
		let posPattern = #"""
		(?xi)data-sourcepos="(\d+):
		"""#
		// swiftlint:disable:next force_try
		return try! NSRegularExpression(pattern: posPattern, options: .caseInsensitive)
	}()

	public init(previewId: Int, fileId: Int, workspace: AppWorkspace, document: RmdDocument?) {
		self.previewId = previewId
		self.fileId = fileId
		self.workspace = workspace
		self.document = document

		guard let regex = try? NSRegularExpression(pattern: "\\s+\\\\$", options: [.anchorsMatchLines]),
			  let openRegex = try? NSRegularExpression(pattern: "^\\$\\$", options: []),
			  let closeRegex = try? NSRegularExpression(pattern: "\\$\\$(\\s*)$", options: [])
		else { fatalError("regex failed to compile") }
		lineContiuationRegex = regex
		openDoubleDollarRegex = openRegex
		closeDoubleDollarRegex = closeRegex

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
		guard let curDoc = document else { return }
		var changedChunkIndexes = [Int](0..<curDoc.chunks.count)
		cacheCode(changedChunks: &changedChunkIndexes)
	}

	/// caches the html for all code chunks and any markdown chunks that contain inline code
	// TODO: this needs to return a SignalHandler so the code can be executed async
	/// - Parameter changedChunks: array of chunkNumbers that caller thinks changed.
	///  Any chunk where the output did not change is removed. Ones not included where the output did change are added.
	/// - Parameter document: the document to cache
	// swiftlint:disable:next cyclomatic_complexity
	public func cacheCode(changedChunks: inout [Int]) {
		guard let curDoc = document else { Log.warn("asked to cache without a document"); return }
		// if not the same size as last time, then all code is dirty
		if curDoc.chunks.count != chunkInfo.count {
			chunkInfo = [ChunkInfo]()
			for i in 0..<curDoc.chunks.count {
				chunkInfo.append(ChunkInfo(chunkNumber: i, type: RootChunkType(curDoc.chunks[i].chunkType)))
			}
		}
		// generate html for each chunk.
		for (chunkNumber, chunk) in curDoc.chunks.enumerated() {
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
			let currentHtml = htmlForCodeChunk(chunkNumber: chunkNumber)
			if chunkInfo[chunkNumber].currentHtml != currentHtml {
				chunkInfo[chunkNumber].currentHtml = currentHtml
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
	
	/// calls supplied closure for every chunk whose output is invalid
	/// - Parameter body: closure to call
	public func forInvalidChunks(body: (Int) -> Void) {
		chunkInfo.filter({ !$0.outputIsValid }).forEach({ body($0.chunkNumber) })
	}
	
	/// Figures out the state for every chunk
	/// - Returns: Tuple of  ( [chunkNumber], [Bool]) where second array is true if it should be enabled
	public func chunksValidity() -> ([Int], [Bool]) {
		var indexes = [Int]()
		var enable = [Bool]()
			chunkInfo.forEach {
				indexes.append($0.chunkNumber)
				enable.append(!$0.outputIsValid)
		}
		return (indexes, enable)
	}
	
	/// Called to notify a chunk will be execute. Invalidates the output of all code chunks that foillow
	/// - Parameter chunkIndex: the chunkIndex
	public func willExecuteChunk(chunkIndex: Int) {
		precondition(chunkInfo.indices.contains(chunkIndex))
		// invalidate all future code chunks
		for idx in chunkIndex..<chunkInfo.count where chunkInfo[idx].type == .code {
			chunkInfo[idx].outputIsValid = false
		}

	}
	
	/// Reports if the specified's output is valid and doesn't need updating
	/// - Parameter number: the chunk number
	/// - Returns: true if the otuput is known to be valid
	public func isChunkOutputValid(chunkIndex: Int) -> Bool {
		chunkInfo[chunkIndex].outputIsValid
	}
	
	public func htmlFor(chunk: RmdDocumentChunk, index: Int) -> String {
		guard let curDoc = document else { fatalError("code handler called w/o a document") }
		switch RootChunkType(chunk.chunkType) {
		case .code:
			return htmlForCodeChunk(chunkNumber: index)
		case .markdown:
			return htmlFor(markdownChunk: chunk, index: index)
		case .equation:
			return htmlForEquation(chunk: chunk, curDoc: curDoc)
		}
	}
	
	public func inlineHtmlFor(chunk: RmdDocumentChunk, parent: RmdDocumentChunk) -> String {
		guard let curDoc = document else { fatalError("code handler called w/o a document") }
		// just return nothing if not code
		guard chunk.isInline else { return "" }
		guard chunk.chunkType == .inlineCode else {
			return markdownFor(inlineEquation: chunk, curDoc: curDoc)
		}
		// TODO: generate actual code. need to be able to tell what context to use
		let parHTML = curDoc.string(for: chunk, type: .outer)
		return parHTML
	}

	/// returns the html for the specified chunk.
	public func htmlForCodeChunk(chunkNumber: Int) -> String {
		guard let curDoc = document else { fatalError("code handler called w/o a document") }
		let src = curDoc.string(for: curDoc.chunks[chunkNumber], type: .inner)
		let output: String
		if chunkInfo.count > 0, chunkInfo[chunkNumber].output.count > 0 {
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

	func htmlForEquation(chunk: RmdDocumentChunk, curDoc: RmdDocument) -> String {
		var equationText = curDoc.string(for: chunk)
		equationText = lineContiuationRegex.stringByReplacingMatches(in: equationText, range: equationText.fullNSRange, withTemplate: "")
		equationText = openDoubleDollarRegex.stringByReplacingMatches(in: equationText, range: equationText.fullNSRange, withTemplate: "\\\\[")
		equationText = closeDoubleDollarRegex.stringByReplacingMatches(in: equationText, range: equationText.fullNSRange, withTemplate: "\\\\]")
		equationText = equationText.addingUnicodeEntities
		return "\n<div class=\"equation\">\(equationText)</div>\n"
		
	}
	
	private func markdownFor(inlineEquation: RmdDocumentChunk, curDoc: RmdDocument) -> String {
		var code = curDoc.string(for: inlineEquation, type: .inner)
		code = code.replacingOccurrences(of: "^\\$", with: "\\(", options: .regularExpression)
		code = code.replacingOccurrences(of: "\\$$\\s", with: "\\) ", options: .regularExpression)
		return "<span class\"math inline\">\n\(code)</span>"
	}
	
	func htmlFor(markdownChunk: RmdDocumentChunk, index: Int) -> String {
		guard let curDoc = document else { fatalError("code handler called w/o a document") }
		var chunkString = curDoc.string(for: markdownChunk)
		let html: NSMutableString
		if markdownChunk.children.count > 0 {
			// replace all inline chunks with a placeholder
			for idx in (0..<markdownChunk.children.count).reversed() {
				guard let range = Range<String.Index>(markdownChunk.children[idx].chunkRange, in: chunkString) else { fatalError("invalid range") }
				chunkString = chunkString.replacingCharacters(in: range, with: "!IC-\(idx)!")
			}
			// convert markdown to html
			html = mdownParser.htmlFor(markdown: chunkString)
			// restore inline chunks. reverse so don't invalidate later ranges
			for idx in (0..<markdownChunk.children.count) {
				let replacement = markdownFor(inlineEquation: markdownChunk.children[idx], curDoc: curDoc)
				html.replaceOccurrences(of: "!IC-\(idx)!", with: replacement, options: [], range: NSRange(location: 0, length: html.length))
			}
		} else {
			html = mdownParser.htmlFor(markdown: chunkString)
		}
		// modify source position to include chunk number
		_ = dataSourceRegex.replaceMatches(in: html, range: NSRange(location: 0, length: html.length), withTemplate: "data-sourcepos=\"\(index).$2")
		return html as String
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
//		do {
//			try dbQueue!.read { db in
//				do {
//					if let oldRec = try SavedCacheEntry.fetchOne(db, sql: "select * FROM \(cacheTableName) where fileID = \(fileId)")
//					{
//						self.chunkInfo = oldRec.chunks
//					}
//				} catch {
//					Log.warn("error reading cache: \(error)", .app)
//					throw error
//				}
//			}
//		} catch {
//				Log.warn("error reading cache: \(error)", .app)
//		}
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
