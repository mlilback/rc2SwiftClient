//
//  EditorDocument.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import os
import ReactiveSwift
import Networking

let MinTimeBetweenAutoSaves:TimeInterval = 2

class EditorDocument: NSObject {
	typealias SaveSignalProducer = SignalProducer<(old: String, new: String), NSError>
	
	fileprivate(set) var file: File
	let fileUrl: URL
	let fileCache:  FileCache
	let undoManager: UndoManager
	fileprivate(set) var savedContents: String?
	var editedContents: String?
	fileprivate(set) var lastSaveTime:TimeInterval = 0
	var topVisibleIndex: Int = 0
	fileprivate(set) var isLoaded: Bool = false

	var currentContents: String {
		assert(isLoaded);
		return editedContents != nil ? editedContents! : savedContents!
	}
	var dirty: Bool {
		if nil == editedContents { return false }
		return editedContents != savedContents
	}

	init(file: File, fileCache: FileCache) {
		self.file = file
		self.fileCache = fileCache
		self.fileUrl = fileCache.cachedUrl(file: file)
		self.undoManager = UndoManager()
		super.init()
	}

	func loadContents() -> SignalProducer<String, NSError> {
		return SignalProducer<String, NSError>() { observer, _ in
			guard nil == self.savedContents else {
				observer.send(value: self.savedContents!)
				observer.sendCompleted()
				return
			}
			self.fileCache.contents(of: self.file).startWithResult { result in
				guard let data = result.value else {
					//TODO: handle error
					os_log("failed to load contents of %{public}@: %{public}@", log: .app, self.file.name, result.error!.localizedDescription)
					observer.send(error: result.error! as NSError)
					return
				}
				self.savedContents = String(data: data, encoding: String.Encoding.utf8)
				self.isLoaded = true
				observer.send(value: self.savedContents!)
				observer.sendCompleted()
			}
		}
	}
	
	func willBecomeActive() {
		
	}
	
	func willBecomeInactive(_ text: String?) {
		editedContents = text
	}

	func updateFile(_ newFile: File) {
		precondition(isLoaded)
		self.editedContents = nil
		self.file = newFile
	}
	
	/// - returns: nil if autosave and has been a while since last save, else producer to save contents
	func saveContents(isAutoSave autosave: Bool=false) -> SaveSignalProducer? {
		precondition(isLoaded)
		if autosave {
			let curTime = Date.timeIntervalSinceReferenceDate
			guard curTime - lastSaveTime < MinTimeBetweenAutoSaves else { return nil }
		}
		return SaveSignalProducer { observer, _ in
			self.lastSaveTime = Date.timeIntervalSinceReferenceDate
			self.fileCache.save(file: self.file, contents: self.editedContents!).startWithCompleted {
				self.savedContents = self.editedContents
				self.editedContents = nil
				self.lastSaveTime = Date.timeIntervalSinceReferenceDate
			}
		}
	}
}
