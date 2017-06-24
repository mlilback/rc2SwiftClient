//
//  EditorDocument.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import os
import ReactiveSwift
import Networking
import ClientCore

let MinTimeBetweenAutoSaves: TimeInterval = 2

public class EditorDocument: NSObject {

	fileprivate(set) var file: File
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

	public init(file: File, fileCache: FileCache) {
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
				os_log("error caching new file %{public}@", log:.session, error as NSError)
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
					os_log("failed to load contents of %{public}@: %{public}@", log: .app, self.file.name, result.error!.localizedDescription)
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

	public func updateFile(_ newFile: File) {
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
			os_log("saveContents called when not loaded)")
			return SignalProducer<String, Rc2Error>.empty
		}
		if saveInProgress.value { return SignalProducer<String, Rc2Error>(error: Rc2Error(type: .alreadyInProgress)) }
		return SignalProducer<String, Rc2Error> { observer, _ in
			os_log("EditorDocument.saveContents called", log: .app, type: .info)
			if self.saveInProgress.value || (autosave && !self.needAutosave()) {
				os_log("EditorDocument unnecessary autosave", log: .app, type: .info)
				observer.send(value: self.currentContents)
				observer.sendCompleted()
				return
			}
			self.lastSaveTime = Date.timeIntervalSinceReferenceDate
			os_log("saving contents of file %d", log: .app, type: .info, self.file.fileId)
			self.saveInProgress.value = true
			self.fileCache.save(file: self.file, contents: self.editedContents!).start { event in
				switch event {
				case .completed:
					defer { self.saveInProgress.value = false }
					self.savedContents = self.editedContents
					self.editedContents = nil
					self.lastSaveTime = Date.timeIntervalSinceReferenceDate
					os_log("local save complete", log: .app, type: .info)
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
		os_log("saving contents of file %d", log: .app, type: .info, self.file.fileId)
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
			os_log("save complete", log: .app, type: .info)
			observer.sendCompleted()
		}
	}
	
	///has enough time elapsed since the last save for an autosave
	private func needAutosave() -> Bool {
		let curTime = Date.timeIntervalSinceReferenceDate
		return curTime - self.lastSaveTime >= MinTimeBetweenAutoSaves
	}
}
