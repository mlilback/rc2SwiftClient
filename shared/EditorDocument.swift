//
//  EditorDocument.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

let MinTimeBetweenAutoSaves:NSTimeInterval = 2

class EditorDocument: NSObject {
	let file:File
	let fileUrl:NSURL
	let fileHandler:SessionFileHandler
	let undoManager:NSUndoManager
	private(set) var savedContents:String!
	var editedContents:String?
	private(set) var lastSaveTime:NSTimeInterval = 0
	
	var currentContents:String { return editedContents != nil ? editedContents! : savedContents }
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
		fileHandler.contentsOfFile(file).onSuccess { fileData in
			self.savedContents = String(data: fileData!, encoding: NSUTF8StringEncoding)
		}
	}
	
	func willBecomeActive() {
		
	}
	
	func willBecomeInactive(text:String?) {
		editedContents = text
	}
	
	///any completion blocks added to progress will be executed on the main queue after the
	///save is complete, but before the document replaces the savedContents with the editedContents
	///this allows observers to access the previous and new content
	func saveContents(isAutoSave autosave:Bool=false) -> NSProgress? {
		if autosave {
			let curTime = NSDate.timeIntervalSinceReferenceDate()
			guard curTime - lastSaveTime > MinTimeBetweenAutoSaves else { return nil }
		}
		self.lastSaveTime = NSDate.timeIntervalSinceReferenceDate()
		let prog = NSProgress(totalUnitCount: -1) //indeterminate
		fileHandler.saveFile(file, contents: editedContents!) { err in
			//TODO: show alert to user if save failed, probably should tell caller
			guard nil == err else { return }
			prog.totalUnitCount = 1 //makes it determinate so it can be completed
			prog.rc2_complete(err)
			//let progress handler blocks run first
			dispatch_async(dispatch_get_main_queue()) {
				self.savedContents = self.editedContents
				self.editedContents = nil
				self.lastSaveTime = NSDate.timeIntervalSinceReferenceDate()
			}
		}
		return prog
	}
}
