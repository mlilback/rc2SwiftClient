//
//  EditorDocument.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import MJLLogger
import ReactiveSwift
import Networking
import ClientCore

let minTimeBetweenAutoSaves: TimeInterval = 2

public class EditorDocument: NSObject {

	fileprivate(set) var file: AppFile
	public let fileUrl: URL
	public let fileCache: FileCache
	let undoManager: UndoManager
	fileprivate(set) var savedContents: String?
	public var editedContents: String?
	fileprivate(set) var lastSaveTime: TimeInterval = 0
	var topVisibleIndex: Int = 0
	fileprivate(set) var isLoaded: Bool = false
	private let saveInProgress = Atomic<Bool>(false)

	public var currentContents: String {
		assert(isLoaded)
		return editedContents != nil ? editedContents! : savedContents!
	}
	public var dirty: Bool {
		if nil == editedContents { return false }
		return editedContents != savedContents
	}

	public init(file: AppFile, fileCache: FileCache) {
		self.file = file
		self.fileCache = fileCache
		self.fileUrl = fileCache.cachedUrl(file: file)
		self.undoManager = UndoManager()
		super.init()
		if !fileUrl.fileExists() {
			do {
				savedContents = String(data: try Data(contentsOf: fileUrl), encoding: .utf8)
				isLoaded = true
			} catch {
				Log.warn("error caching new file \(error)", .session)
			}
		}
	}

	public func loadContents() -> SignalProducer<String, Rc2Error> {
		return SignalProducer<String, Rc2Error> { observer, _ in
			guard nil == self.savedContents else {
				observer.send(value: self.savedContents!)
				observer.sendCompleted()
				return
			}
			self.fileCache.contents(of: self.file).startWithResult { result in
				guard let data = result.value else {
					Log.warn("failed to load contents of \(self.file.name): \(result.error!)", .app)
					observer.send(error: result.error!)
					return
				}
				self.savedContents = String(data: data, encoding: String.Encoding.utf8)
				self.isLoaded = true
				observer.send(value: self.savedContents!)
				observer.sendCompleted()
			}
		}
	}

	public func willBecomeActive() {
	}

	public func willBecomeInactive(_ text: String?) {
		editedContents = text
	}

	public func updateFile(_ newFile: AppFile) {
		guard isLoaded else { return }
		precondition(isLoaded)
		self.editedContents = nil
		self.file = newFile
	}

	/// save the contents of the document to disk
	///
	/// - Parameter autosave: true if this is an autosaves. Defaults to false.
	/// - Returns: signal producer that will complete with the contents that were saved
	public func saveContents(isAutoSave autosave: Bool = false) -> SignalProducer<String, Rc2Error> {
		guard isLoaded else {
			Log.warn("saveContents called when not loaded)", .app)
			return SignalProducer<String, Rc2Error>.empty
		}
		if saveInProgress.value { return SignalProducer<String, Rc2Error>(error: Rc2Error(type: .alreadyInProgress)) }
		return SignalProducer<String, Rc2Error> { observer, _ in
			Log.info("EditorDocument.saveContents called", .app)
			if self.saveInProgress.value || (autosave && !self.needAutosave()) {
				Log.info("EditorDocument unnecessary autosave", .app)
				observer.send(value: self.currentContents)
				observer.sendCompleted()
				return
			}
			self.lastSaveTime = Date.timeIntervalSinceReferenceDate
			Log.info("saving contents of file \(self.file.fileId)", .app)
			self.saveInProgress.value = true
			self.fileCache.save(file: self.file, contents: self.editedContents!).start { event in
				switch event {
				case .completed:
					defer { self.saveInProgress.value = false }
					self.savedContents = self.editedContents
					self.editedContents = nil
					self.lastSaveTime = Date.timeIntervalSinceReferenceDate
					Log.info("local save complete", .app)
					observer.send(value: self.savedContents!)
					observer.sendCompleted()
				case .failed(let err):
					defer { self.saveInProgress.value = false }
					observer.send(error: err)
				case .interrupted:
					defer { self.saveInProgress.value = false }
				default:
					break
				}
			}
		}
	}

	///performs the actual save via the fleCache
	private func performActualSave(observer: Signal<String, Rc2Error>.Observer) {
		self.lastSaveTime = Date.timeIntervalSinceReferenceDate
		Log.info("saving contents of file \(self.file.fileId)", .app)
		self.fileCache.save(file: self.file, contents: self.editedContents!).startWithResult { result in
			self.saveInProgress.value = true
			defer { self.saveInProgress.value = false }
			guard result.error == nil else {
				observer.send(error: result.error!)
				return
			}
			self.savedContents = self.editedContents
			self.editedContents = nil
			self.lastSaveTime = Date.timeIntervalSinceReferenceDate
			Log.info("save complete", .app)
			observer.sendCompleted()
		}
	}

	///has enough time elapsed since the last save for an autosave
	private func needAutosave() -> Bool {
		let curTime = Date.timeIntervalSinceReferenceDate
		return curTime - self.lastSaveTime >= minTimeBetweenAutoSaves
	}
}
