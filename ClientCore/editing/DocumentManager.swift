//
//  DocumentManager.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Rc2Common
import ReactiveSwift
import Networking
import SwiftyUserDefaults
import SyntaxParsing
import MJLLogger
import iosMath

public extension Notification.Name {
	/// sent before the currentDocument will be saved. object will be the EditorContext/DocummentManager
	static let willSaveDocument = Notification.Name(rawValue: "DocumentWillSaveNotification")
}

/// Manages open documents and the current document. Provides common properties to editor components via the EditorContext protocol.
public class DocumentManager: EditorContext {
	let minTimeBetweenAutoSaves: TimeInterval = 2
	
	// MARK: properties
	// when changed, should use .updateProgress() while loading file contents
	private let _currentDocument = MutableProperty<EditorDocument?>(nil)
	public let currentDocument: Property<EditorDocument?>
	private let _parsedDocument = MutableProperty<RmdDocument?>(nil)
	public var parsedDocument: Property<RmdDocument?>
	
	public let editorFont: MutableProperty<PlatformFont>
	public var errorHandler: Rc2ErrorHandler { return self }
	private var openDocuments: [Int: EditorDocument] = [:]
	public var notificationCenter: NotificationCenter
	public var workspaceNotificationCenter: NotificationCenter
	public let lifetime: Lifetime
	var defaults: UserDefaults
	private var contentsChangedDisposable: Disposable?
	private var lastParsed: TimeInterval = 0
	private var equationLabel: MTMathUILabel?

	let fileSaver: FileSaver
	let fileCache: FileCache
	let loading = Atomic<Bool>(false)
	let saving = Atomic<Bool>(false)
	public var busy: Bool { return loading.value || saving.value }
	
	// MARK: methods
	
	public init(fileSaver: FileSaver, fileCache: FileCache, lifetime: Lifetime, notificationCenter: NotificationCenter = .default, wspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter, defaults: UserDefaults = .standard)
	{
		currentDocument = Property<EditorDocument?>(_currentDocument)
		parsedDocument = Property<RmdDocument?>(_parsedDocument)
		self.fileSaver = fileSaver
		self.fileCache = fileCache
		self.lifetime = lifetime
		self.notificationCenter = notificationCenter
		self.workspaceNotificationCenter = wspaceCenter
		self.defaults = defaults
		let defaultSize = defaults[.defaultFontSize]
		// font defaults to user-fixed pitch font
		var initialFont = PlatformFont.userFixedPitchFont(ofSize: defaultSize)!
		// try loading a saved font, or if there isn't one, Menlo
		if let fontDesc = defaults[.editorFont], let font = PlatformFont(descriptor: fontDesc, size: fontDesc.pointSize) {
			initialFont = font
		} else if let menlo = PlatformFont(name: "Menlo-Regular", size: defaultSize) {
			initialFont = menlo
		}
		editorFont = MutableProperty<PlatformFont>(initialFont)
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
			switchTo(document: document)
		} else if change.type == .remove {
			//document being editied was removed
			switchTo(document: nil)
		}
	}
	
	/// returns a SP that will save the current document and load the document for file
	public func load(file: AppFile?) -> SignalProducer<String?, Rc2Error> {
		if loading.value {
			Log.warn("load called while already loading", .app)
		}
		// get a producer to save the old document
		let saveProducer: SignalProducer<(), Rc2Error>
		if let curDoc = currentDocument.value {
			saveProducer = save(document: curDoc)
		} else { // make a producer that does nothing
			saveProducer = SignalProducer<(), Rc2Error>(value: ())
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
	
	public func revertCurrentDocument() {
		guard let doc = currentDocument.value else { return }
		// clear autosave document if exists
		let tmpUrl = autosaveUrl(document: doc)
		if tmpUrl.fileExists() {
			try? fileCache.fileManager.removeItem(at: tmpUrl)
		}
		switchTo(document: doc)
	}
	
	/// saves to server, fileCache, and memory cache
	public func save(document: EditorDocument, isAutoSave: Bool = false) -> SignalProducer<(), Rc2Error> {
		if isAutoSave {
			return autosave(document: document)
		}
		notificationCenter.post(name: .willSaveDocument, object: self)
		guard document.isDirty else { return SignalProducer<(), Rc2Error>(value: ()) }
		guard let contents = document.currentContents else {
			return SignalProducer<(), Rc2Error>(error: Rc2Error(type: .invalidArgument))
		}
		return self.fileSaver.save(file: document.file, contents: contents)
			.on(starting: { self.saving.value = true })
			.map { _ in (document.file, contents) }
			.flatMap(.concat, fileCache.save)
			.on(completed: {
				document.contentsSaved()
			},
				terminated: { self.saving.value = false })
	}
	
	/// Generates an image to use for the passed in latex, size based on the editor font's size
	///
	/// - Parameter latex: The latex to use as an inline equation
	/// - Returns: an image of the latex as an inline equation
	public func inlineImageFor(latex: String) -> PlatformImage? {
		if nil == equationLabel {
			equationLabel = MTMathUILabel(frame: CGRect(x: 0, y: 0, width: 1000, height: 20)) // default max size for equation image
			equationLabel?.labelMode = .text
		}
		equationLabel?.fontSize = editorFont.value.pointSize
		equationLabel?.latex = latex
		equationLabel?.layout()
		guard let dlist = equationLabel?.displayList else {
			print("error with list no list")
			return nil
		}
		let size = equationLabel!.intrinsicContentSize
		let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
		let nscontext = NSGraphicsContext(bitmapImageRep: rep)!
		NSGraphicsContext.saveGraphicsState()
		NSGraphicsContext.current = nscontext
		dlist.draw(nscontext.cgContext)
		NSGraphicsContext.restoreGraphicsState()
		let image = NSImage(size: size)
		image.addRepresentation(rep)
		return image
	}
	
	// MARK: - private methods
	/// actually autosaves a file
	private func autosave(document: EditorDocument) -> SignalProducer<(), Rc2Error> {
		guard UserDefaults.standard[.autosaveEnabled] else {
			Log.info("skipping autosave", .app)
			return SignalProducer<(), Rc2Error>(value: ())
		}
		Log.info("autosaving \(document.file.name)", .core)
		let tmpUrl = autosaveUrl(document: document)
		return SignalProducer<(), Rc2Error> { [weak self] observer, _ in
			var err: Rc2Error?
			defer {
				if let err = err {
					observer.send(error: err)
				} else {
					observer.send(value: ())
					observer.sendCompleted()
				}
			}
			guard let me = self else { return }
			me.notificationCenter.post(name: .willSaveDocument, object: self)
			if let content = document.savedContents {
				do {
					try Data(content.utf8).write(to: tmpUrl)
					document.file.writeXAttributes(tmpUrl)
					Log.info("autosaved \(tmpUrl.lastPathComponent)", .core)
				} catch {
					err = Rc2Error(type: .file, nested: error, explanation: "failed to autosave \(tmpUrl.lastPathComponent)")
				}
			}
		}
	}
	
	private func autosaveUrl(document: EditorDocument) -> URL {
		return fileCache.fileCacheUrl.appendingPathComponent("~\(document.file.fileId).\(document.file.fileType.fileExtension)")
	}

	private func nilOutCurrentDocument() -> SignalProducer<String?, Rc2Error> {
		return SignalProducer<String?, Rc2Error>(value: nil)
			.on(started: { self.switchTo(document: nil) })
	}
	
	// the only function that should change _currentDocument, so that parsedDocument is updated appropriately
	private func switchTo(document: EditorDocument?) {
		// parsed is updated on a later cycle of the main thread
		contentsChangedDisposable?.dispose()
		_currentDocument.value = document
		contentsChangedDisposable = document?.editedContents.signal.observeValues { [weak self] _ in
			// if contents changed, need to reparse
			self?.parseCurrentDocument()
		}
		DispatchQueue.main.async {
			self.parseCurrentDocument()
		}
	}
	
	private func parseCurrentDocument() {
		guard let document = currentDocument.value, document.parsable else {
			_parsedDocument.value = nil
			return
		}
		do {
			let newParsed = try RmdDocument(contents: document.currentContents ?? "") { (topic) in
				return HelpController.shared.hasTopic(topic)
			}
			Log.info("parsed \(document.file.name) with \(newParsed.chunks.count) chunks", .core)
			_parsedDocument.value = newParsed
		} catch {
			Log.info("failed to parse document \(document.file.name)", .core)
		}
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
			switchTo(document: document)
			return SignalProducer<String?, Rc2Error>(value: document.currentContents)
		}
		// see if there is autosave data to use
		let tmpUrl = autosaveUrl(document: document)
		if tmpUrl.fileExists(),
			document.file.versionXAttributesMatch(url: tmpUrl),
			let contents = try? String(contentsOf: tmpUrl, encoding: .utf8)
		{
			Log.info("using contents from autosave file (\(document.file.fileId))", .core)
			return SignalProducer<String?, Rc2Error>(value: contents)
		}
		// read cache
		if fileCache.isFileCached(document.file) {
			return fileCache.contents(of: document.file)
				.on(value: { _ in self.switchTo(document: document) })
				.map( { String(data: $0, encoding: .utf8) } )
		}
		// load from network
		return fileCache.validUrl(for: document.file)
			.map({ _ in return document.file })
			.flatMap(.concat, fileCache.contents)
			.on(value: { _ in self.switchTo(document: document) })
			.map( { String(data: $0, encoding: .utf8) } )
	}
}

extension DocumentManager: Rc2ErrorHandler {
	public func handle(error: Rc2Error) {
		
	}
}
