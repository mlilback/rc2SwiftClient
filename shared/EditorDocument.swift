//
//  EditorDocument.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import BrightFutures
import os

let MinTimeBetweenAutoSaves:TimeInterval = 2

class EditorDocument: NSObject {
	let oldContentsUserInfoKey = "OldContentsUserInfoKey"

	fileprivate(set) var file:File
	let fileUrl:URL
	let fileHandler:SessionFileHandler
	let undoManager:UndoManager
	fileprivate(set) var savedContents:String?
	var editedContents:String?
	fileprivate(set) var lastSaveTime:TimeInterval = 0
	var topVisibleIndex:Int = 0
	fileprivate(set) var isLoaded:Bool = false
	
	var currentContents:String {
		assert(isLoaded);
		return editedContents != nil ? editedContents! : savedContents!
	}
	var dirty:Bool {
		if nil == editedContents { return false }
		return editedContents != savedContents
	}
	
	init(file:File, fileHandler:SessionFileHandler) {
		self.file = file
		self.fileHandler = fileHandler
		self.fileUrl = fileHandler.fileCache.cachedUrl(file:file)
		self.undoManager = UndoManager()
		super.init()
	}
	
	func loadContents() -> Future<String, NSError> {
		let promise = Promise<String, NSError>()
		if nil == savedContents {
			fileHandler.contentsOfFile(file).onSuccess { fileData in
				self.savedContents = String(data: fileData! as Data, encoding: String.Encoding.utf8)
				self.isLoaded = true
				promise.success(self.savedContents!)
			}.onFailure { error in
				//TODO: handle error
				os_log("failed to load contents of %{public}%@: %{public}@", self.file.name, error as NSError)
				promise.failure(error as NSError)
			}
		}
		return promise.future
	}
	
	func willBecomeActive() {
		
	}
	
	func willBecomeInactive(_ text:String?) {
		editedContents = text
	}
	
	func updateFile(_ newFile:File) {
		precondition(isLoaded)
		self.editedContents = nil
		self.file = newFile
	}
	
	///any completion blocks added to progress will be executed on the main queue after the
	///save is complete, but before the document replaces the savedContents with the editedContents
	///this allows observers to access the previous and new content
	///@returns nil if autosave and has been a while since last save, else progress
	func saveContents(isAutoSave autosave:Bool=false) -> Progress? {
		precondition(isLoaded)
		if autosave {
			let curTime = Date.timeIntervalSinceReferenceDate
			guard curTime - lastSaveTime < MinTimeBetweenAutoSaves else { return nil }
		}
		self.lastSaveTime = Date.timeIntervalSinceReferenceDate
		let prog = Progress(totalUnitCount: -1) //indeterminate
		fileHandler.saveFile(file, contents: editedContents!) { err in
			//only mark self as saved if no error
			if err == nil {
				self.savedContents = self.editedContents
				self.editedContents = nil
				self.lastSaveTime = Date.timeIntervalSinceReferenceDate
			}
			//mark progress complete, reporting error if there was one
			prog.totalUnitCount = 1 //makes it determinate so it can be completed
			prog.setUserInfoObject(self.savedContents, forKey: ProgressUserInfoKey(rawValue: self.oldContentsUserInfoKey))
			prog.rc2_complete(err) //complete with an error
		}
		return prog
	}
}
