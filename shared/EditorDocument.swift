//
//  EditorDocument.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import BrightFutures

let MinTimeBetweenAutoSaves:NSTimeInterval = 2

class EditorDocument: NSObject {
	let oldContentsUserInfoKey = "OldContentsUserInfoKey"

	private(set) var file:File
	let fileUrl:NSURL
	let fileHandler:SessionFileHandler
	let undoManager:NSUndoManager
	private(set) var savedContents:String?
	var editedContents:String?
	private(set) var lastSaveTime:NSTimeInterval = 0
	var topVisibleIndex:Int = 0
	private(set) var isLoaded:Bool = false
	
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
		self.fileUrl = fileHandler.fileCache.cachedFileUrl(file)
		self.undoManager = NSUndoManager()
		super.init()
	}
	
	func loadContents() -> Future<String, NSError> {
		let promise = Promise<String, NSError>()
		if nil == savedContents {
			fileHandler.contentsOfFile(file).onSuccess { fileData in
				self.savedContents = String(data: fileData!, encoding: NSUTF8StringEncoding)
				self.isLoaded = true
				promise.success(self.savedContents!)
			}.onFailure { error in
				//TODO: handle error
				log.error("failed to load contents of \(self.file.name): \(error)")
				promise.failure(error as NSError)
			}
		}
		return promise.future
	}
	
	func willBecomeActive() {
		
	}
	
	func willBecomeInactive(text:String?) {
		editedContents = text
	}
	
	func updateFile(newFile:File) {
		precondition(isLoaded)
		self.editedContents = nil
		self.file = newFile
	}
	
	///any completion blocks added to progress will be executed on the main queue after the
	///save is complete, but before the document replaces the savedContents with the editedContents
	///this allows observers to access the previous and new content
	///@returns nil if autosave and has been a while since last save, else progress
	func saveContents(isAutoSave autosave:Bool=false) -> NSProgress? {
		precondition(isLoaded)
		if autosave {
			let curTime = NSDate.timeIntervalSinceReferenceDate()
			guard curTime - lastSaveTime < MinTimeBetweenAutoSaves else { return nil }
		}
		self.lastSaveTime = NSDate.timeIntervalSinceReferenceDate()
		let prog = NSProgress(totalUnitCount: -1) //indeterminate
		fileHandler.saveFile(file, contents: editedContents!) { err in
			//only mark self as saved if no error
			if err == nil {
				self.savedContents = self.editedContents
				self.editedContents = nil
				self.lastSaveTime = NSDate.timeIntervalSinceReferenceDate()
			}
			//mark progress complete, reporting error if there was one
			prog.totalUnitCount = 1 //makes it determinate so it can be completed
			prog.setUserInfoObject(self.savedContents, forKey: self.oldContentsUserInfoKey)
			prog.rc2_complete(err) //complete with an error
		}
		return prog
	}
}
