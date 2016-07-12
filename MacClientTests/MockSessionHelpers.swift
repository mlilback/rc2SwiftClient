//
//  MockSessionHelpers.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import BrightFutures
@testable import MacClient
import XCTest

struct MockFileEntry {
	let file:File
	let url:NSURL
}

class MockFileCache: FileCache {
	var fileManager:FileManager
	var cachedFiles = [Int:MockFileEntry]()
	
	init(fileManager fm:FileManager) {
		self.fileManager = fm
	}
	
	func append(file:File, url:NSURL) {
		cachedFiles[file.fileId] = MockFileEntry(file: file, url: url)
	}
	
	func isFileCached(file:File) -> Bool {
		return cachedFiles[file.fileId] != nil
	}
	
	func flushCacheForWorkspace(wspace:Workspace) {
	}
	
	///recaches the specified file if it has changed
	func flushCacheForFile(file:File) -> NSProgress? {
		cachedFiles.removeValueForKey(file.fileId)
		return nil
	}
	
	///caches all the files in the workspace that aren't already cached with the current version of the file
	//observer fractionCompleted on returned progress for completion handling
	func cacheAllFiles(setupHandler:((NSProgress)-> Void)) -> NSProgress? {
		return nil
	}
	
	///returns the file system url where the file is/will be stored
	func cachedFileUrl(file:File) -> NSURL {
		let theFile = cachedFiles[file.fileId]
		XCTAssertNotNil(theFile)
		return theFile!.url
	}
}

class MockSessionFileHandler: SessionFileHandler {
	let mockFileCache:MockFileCache
	var workspace:Workspace
	var fileCache:FileCache { return mockFileCache }
	var fileDelegate:SessionFileHandlerDelegate?
	
	init(wspace:Workspace, fileManager:FileManager) {
		self.workspace = wspace
		self.mockFileCache = MockFileCache(fileManager: fileManager)
	}
	
	func loadFiles() -> Future<SessionFileHandler, NSError> {
		let promise = Promise<SessionFileHandler, NSError>()
		promise.success(self)
		return promise.future
	}
	
	///handle file change that requires refetching contents
	func handleFileUpdate(file:File, change:FileChangeType) {
		log.warning("handleFileUpdate not implemented")
		XCTFail()
	}
	
	//handle file change that might contain the file's contents
	func updateFile(file:File, withData data:NSData?) -> NSProgress? {
		log.warning("udpateFile not implemented")
		XCTFail()
		return nil
	}
	
	func contentsOfFile(file:File) -> Future<NSData?,FileError> {
		let promise = Promise<NSData?,FileError>()
		if let entry = mockFileCache.cachedFiles[file.fileId] {
			let fdata = NSData(contentsOfURL: entry.url)
			promise.success(fdata)
		} else {
			XCTFail("no such file in cache")
			promise.failure(.FileNotFound)
		}
		return promise.future
	}
	
	//the following will add the save operation to a serial queue to be executed immediately
	func saveFile(file:File, contents:String, completionHandler:(NSError?) -> Void) {
		var error:NSError? = nil
		let url = fileCache.cachedFileUrl(file)
		do {
			try contents.writeToURL(url, atomically: true, encoding: NSUTF8StringEncoding)
		} catch let err as NSError? {
			log.error("error saving file \(file): \(err)")
			error = err
		}
		completionHandler(error)
	}
}
