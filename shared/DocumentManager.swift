//
//  DocumentManager.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import ClientCore
import ReactiveSwift
import Networking
import SwiftyUserDefaults
import SyntaxParsing

class DocumentManager: EditorContext {
	enum State { case idle, loading, saving }
	let minTimeBetweenAutoSaves: TimeInterval = 2
	
	private var state: State = .idle
	// when changed, should use .updateProgress() while loading file contents
	let currentDocument = MutableProperty<Document?>(nil)
	let editorFont: MutableProperty<NSFont>
	var openDocuments: [Int: Document] = [:]
	var parser: SyntaxParser?
	var notificationCenter: NotificationCenter
	var defaults: UserDefaults
	//	var session: Session
	let fileSaver: FileSaver
	let fileCache: FileCache
	
	init(fileSaver: FileSaver, fileCache: FileCache, notificationCenter: NotificationCenter = .default, defaults: UserDefaults = .standard)
	{
		self.fileSaver = fileSaver
		self.fileCache = fileCache
		self.notificationCenter = notificationCenter
		self.defaults = defaults
		let defaultSize = defaults[.defaultFontSize]
		// font defaults to user-fixed pitch font
		var initialFont = NSFont.userFixedPitchFont(ofSize: defaultSize)!
		// try loading a saved font, or if there isn't one, Menlo
		if let fontDesc = defaults[.editorFont], let font = NSFont(descriptor: fontDesc, size: fontDesc.pointSize) {
			initialFont = font
		} else if let menlo = NSFont(name: "Menlo-Regular", size: defaultSize) {
			initialFont = menlo
		}
		editorFont = MutableProperty<NSFont>(initialFont)
	}
	
	// returns a SP that will save the current document and load the document for file
	func load(file: AppFile?) -> SignalProducer<String?, Rc2Error> {
		// if file is nil, nil out current document
		guard let theFile = file else {
			return setState(desired: .loading)
				.flatMap(.concat, nilOutCurrentDocument)
				.on(completed: { self.state = .idle })
		}
		// get a producer to save the old document
		let saveProducer: SignalProducer<String, Rc2Error>
		if let curDoc = currentDocument.value {
			saveProducer = save(document: curDoc)
		} else { // make a producer that does nothing
			saveProducer = SignalProducer<String, Rc2Error>(value: "")
		}
		// save current document, get the document to load, and load it
		return saveProducer
			.map { _ in theFile }
			.flatMap(.concat, getDocumentFor)
			.flatMap(.concat, load)
	}
	
	// saves to server, fileCache, and memory cache
	func save(document: Document) -> SignalProducer<String, Rc2Error> {
		guard let contents = document.editedContents else {
			return SignalProducer<String, Rc2Error>(error: Rc2Error(type: .invalidArgument))
		}
		return setState(desired: .saving)
			.flatMap(.concat, { self.fileSaver.save(file: document.file, contents: contents) })
			.map { _ in (document.file, contents) }
			.flatMap(.concat, fileCache.save)
			.on(completed: { document.contentsSaved() })
			.map { return document.currentContents ?? "" }
	}
	

	private func  nilOutCurrentDocument() -> SignalProducer<String?, Rc2Error> {
		return SignalProducer<String?, Rc2Error>(value: nil)
			.on(started: { self.currentDocument.value = nil })
	}
	
	// throws an error if state isn't idle, then sets state to the desired value
	private func setState(desired: State) -> SignalProducer<Void, Rc2Error> {
		return SignalProducer<Void, Rc2Error> { observer, _ in
			guard self.state == .idle else {
				observer.send(error: Rc2Error(type: .alreadyInProgress))
				return
			}
			self.state = desired
			observer.sendCompleted()
		}
	}
	
	// returns SP to return the specified document, creating and inserting into openDocuments if necessary
	private func getDocumentFor(file: AppFile) -> SignalProducer<Document, Rc2Error> {
		let doc = openDocuments[file.fileId] ?? Document(file: file, fileUrl: fileCache.cachedUrl(file: file))
		openDocuments[file.fileId] = doc
		return SignalProducer<Document, Rc2Error>(value: doc)
	}
	private func load(document: Document) -> SignalProducer<String?, Rc2Error> {
		precondition(openDocuments[document.file.fileId] == document)
		if document.isLoaded {
			return SignalProducer<String?, Rc2Error>(value: document.currentContents)
		}
		if fileCache.isFileCached(document.file) {
			return fileCache.contents(of: document.file)
				.map( { String(data: $0, encoding: .utf8) } )
		}
		return fileCache.validUrl(for: document.file)
			.map({ _ in return document.file })
			.flatMap(.concat, fileCache.contents)
			.map( { String(data: $0, encoding: .utf8) } )
	}
}
