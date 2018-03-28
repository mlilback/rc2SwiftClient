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
import MJLLogger

extension Notification.Name {
	/// sent before the currentDocument will be saved. object will be the EditorContext/DocummentManager
	static let willSaveDocument = Notification.Name(rawValue: "DocumentWillSaveNotification")
}

/// Manages open documents and the current document. Provides common properties to editor components via the EditorContext protocol.
class DocumentManager: EditorContext {
	let minTimeBetweenAutoSaves: TimeInterval = 2
	
	// MARK: properties
	// when changed, should use .updateProgress() while loading file contents
	private let _currentDocument = MutableProperty<EditorDocument?>(nil)
	let currentDocument: Property<EditorDocument?>
	let editorFont: MutableProperty<NSFont>
	var openDocuments: [Int: EditorDocument] = [:]
	var notificationCenter: NotificationCenter
	var workspaceNotificationCenter: NotificationCenter
	let lifetime: Lifetime
	var defaults: UserDefaults
	//	var session: Session
	let fileSaver: FileSaver
	let fileCache: FileCache
	let loading = Atomic<Bool>(false)
	let saving = Atomic<Bool>(false)
	var busy: Bool { return loading.value || saving.value }
	
	// MARK: methods
	init(fileSaver: FileSaver, fileCache: FileCache, lifetime: Lifetime, notificationCenter: NotificationCenter = .default, wspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter, defaults: UserDefaults = .standard)
	{
		currentDocument = Property<EditorDocument?>(_currentDocument)
		self.fileSaver = fileSaver
		self.fileCache = fileCache
		self.lifetime = lifetime
		self.notificationCenter = notificationCenter
		self.workspaceNotificationCenter = wspaceCenter
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
		fileSaver.workspace.fileChangeSignal.observeValues { [weak self] changes in
			self?.process(changes: changes)
		}
	}
	
	func process(changes: [AppWorkspace.FileChange]) {
		guard !busy else { Log.info("skipping filechange message", .app); return }
		// only care about change if it is our current document
		guard let document = currentDocument.value,
			let change = changes.first(where: { $0.file.fileId == document.file.fileId })
		else { return }
		if change.type == .modify {
			guard document.file.fileId == change.file.fileId else { return }
			document.fileUpdated()
			_currentDocument.value = document
		} else if change.type == .remove {
			//document being editied was removed
			_currentDocument.value = nil
		}
	}
	
	/// returns a SP that will save the current document and load the document for file
	func load(file: AppFile?) -> SignalProducer<String?, Rc2Error> {
		if loading.value {
			Log.warn("load called while already loading", .app)
		}
		// get a producer to save the old document
		let saveProducer: SignalProducer<String, Rc2Error>
		if let curDoc = currentDocument.value {
			saveProducer = save(document: curDoc)
		} else { // make a producer that does nothing
			saveProducer = SignalProducer<String, Rc2Error>(value: "")
		}
		// if file is nil, nil out current document (saving current first)
		guard let theFile = file else {
			return saveProducer
				.on(starting: {	self.loading.value = true })
				.map { _ in () }
				.flatMap(.concat, nilOutCurrentDocument)
				.on(terminated: { self.loading.value = false })
		}
		// save current document, get the document to load, and load it
		return saveProducer
			.map { _ in theFile }
			.flatMap(.concat, getDocumentFor)
			.flatMap(.concat, load)
			.on(starting: { self.loading.value = true }, completed: { self.loading.value = false })
	}
	
	/// saves to server, fileCache, and memory cache
	func save(document: EditorDocument, isAutoSave: Bool = false) -> SignalProducer<String, Rc2Error> {
		// FIXME: use autosave parameter
		guard document.isDirty else { return SignalProducer<String, Rc2Error>(value: document.savedContents!) }
		guard let contents = document.editedContents else {
			return SignalProducer<String, Rc2Error>(error: Rc2Error(type: .invalidArgument))
		}
		notificationCenter.post(name: .willSaveDocument, object: self)
		return self.fileSaver.save(file: document.file, contents: contents)
			.on(starting: { self.saving.value = true })
			.map { _ in (document.file, contents) }
			.flatMap(.concat, fileCache.save)
			.on(completed: { document.contentsSaved() },
				terminated: { self.saving.value = false })
			.map { return document.currentContents ?? "" }
	}
	

	private func  nilOutCurrentDocument() -> SignalProducer<String?, Rc2Error> {
		return SignalProducer<String?, Rc2Error>(value: nil)
			.on(started: { self._currentDocument.value = nil })
	}
	
	// returns SP to return the specified document, creating and inserting into openDocuments if necessary
	private func getDocumentFor(file: AppFile) -> SignalProducer<EditorDocument, Rc2Error> {
		let doc = openDocuments[file.fileId] ?? EditorDocument(file: file, fileUrl: fileCache.cachedUrl(file: file))
		openDocuments[file.fileId] = doc
		guard doc.isLoaded else {
			return fileCache.contents(of: file)
				.map { String(data: $0, encoding: .utf8)! }
				.on(value: { doc.contentsLoaded(contents: $0) })
				.map { _ in doc }
		}
		return SignalProducer<EditorDocument, Rc2Error>(value: doc)
	}
	
	private func load(document: EditorDocument) -> SignalProducer<String?, Rc2Error> {
		precondition(openDocuments[document.file.fileId] == document)
		if document.isLoaded {
			_currentDocument.value = document
			return SignalProducer<String?, Rc2Error>(value: document.currentContents)
		}
		if fileCache.isFileCached(document.file) {
			return fileCache.contents(of: document.file)
				.on(value: { _ in self._currentDocument.value = document })
				.map( { String(data: $0, encoding: .utf8) } )
		}
		return fileCache.validUrl(for: document.file)
			.map({ _ in return document.file })
			.flatMap(.concat, fileCache.contents)
			.on(value: { _ in self._currentDocument.value = document })
			.map( { String(data: $0, encoding: .utf8) } )
	}
}
