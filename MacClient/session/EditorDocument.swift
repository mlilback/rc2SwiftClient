//
//  EditorDocument.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

class EditorDocument: NSObject {
	let file:File
	private var cachedContents:String!
	private var shouldCache = true
	let undoManager:NSUndoManager
	
	init(file:File) {
		log.info("creating EditorDocument \(file.fileId)")
		self.file = file
		self.undoManager = NSUndoManager()
		super.init()
	}
	
	func willBecomeActive() {
		
	}
	
	func wilLBecomeInactive() {
		
	}
}
