//
//  MockSessionHelpers.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
@testable import MacClient
import ClientCore
import ReactiveSwift
import XCTest
import os
import Networking

struct MockFileEntry {
	let file: File
	let url: URL
}

class MockFileCache: FileCache {
	func close() {
	}
	
	var fileManager: Rc2FileManager
	var workspace: Workspace
	
	var cachedFiles = [Int: MockFileEntry]()
	
	init(fileManager fm: Rc2FileManager, workspace: Workspace) {
		self.fileManager = fm
		self.workspace = workspace
	}
	
	func append(file: File, url: URL) {
		cachedFiles[file.fileId] = MockFileEntry(file: file, url: url)
	}
	
	func isFileCached(_ file: File) -> Bool {
		return cachedFiles[file.fileId] != nil
	}
	
	func flushCache(file: File) {
	}
	
	func flushCache(files: [File]) -> SignalProducer<Double, Rc2Error> {
		return SignalProducer<Double, Rc2Error>.init(value: 1.0)
	}
	
	func recache(file: File) -> SignalProducer<Double, Rc2Error> {
		return SignalProducer<Double, Rc2Error>.init(value: 1.0)
	}
	
	///caches all the files in the workspace that aren't already cached with the current version of the file
	//observer fractionCompleted on returned progress for completion handling
	func cacheAllFiles() -> SignalProducer<Double, Rc2Error> {
		return SignalProducer<Double, Rc2Error>.init(value: 1.0)
	}
	
	///returns the file system url where the file is/will be stored
	func cachedUrl(file:File) -> URL {
		let theFile = cachedFiles[file.fileId]
		XCTAssertNotNil(theFile)
		return theFile!.url
	}
	
	func validUrl(for file: File) -> SignalProducer<URL, Rc2Error> {
		return SignalProducer<URL, Rc2Error>(value: cachedUrl(file: file))
	}
	
	func contents(of file: File) -> SignalProducer<Data, Rc2Error> {
		let fileUrl = cachedUrl(file: file)
		return SignalProducer<Data, Rc2Error>(value: try! Data(contentsOf: fileUrl))
	}
	
	func update(file: File, withData data: Data?) -> SignalProducer<Void, Rc2Error> {
		return SignalProducer<Void, Rc2Error>(value: ())
	}
	
	func save(file: File, contents: String) -> SignalProducer<Void, Rc2Error> {
		return SignalProducer<Void, Rc2Error>(value: ())
	}
}

//class MockSessionFileHandler: SessionFileHandler {
//	let mockFileCache:MockFileCache
//	var workspace:Workspace
//	var fileCache:FileCache { return mockFileCache }
//	var fileDelegate:SessionFileHandlerDelegate?
//	
//	init(wspace:Workspace, fileManager:Rc2FileManager) {
//		self.workspace = wspace
//		self.mockFileCache = MockFileCache(fileManager: fileManager)
//	}
//	
//	func loadFiles() -> Future<SessionFileHandler, NSError> {
//		let promise = Promise<SessionFileHandler, NSError>()
//		promise.success(self)
//		return promise.future
//	}
//	
//	///handle file change that requires refetching contents
//	func handleFileUpdate(_ file:File, change:FileChangeType) {
//		os_log("handleFileUpdate not implemented")
//		XCTFail()
//	}
//	
//	//handle file change that might contain the file's contents
//	@discardableResult func updateFile(_ file:File, withData data:Data?) -> Progress? {
//		os_log("updateFile not implemented")
//		XCTFail()
//		return nil
//	}
//	
//	func contentsOfFile(_ file:File) -> Future<Data?,FileError> {
//		let promise = Promise<Data?,FileError>()
//		if let entry = mockFileCache.cachedFiles[file.fileId] {
//			let fdata = try! Data(contentsOf: entry.url)
//			promise.success(fdata)
//		} else {
//			XCTFail("no such file in cache")
//			promise.failure(.fileNotFound)
//		}
//		return promise.future
//	}
//	
//	//the following will add the save operation to a serial queue to be executed immediately
//	func saveFile(_ file:File, contents:String, completionHandler: @escaping (NSError?) -> Void) {
//		var error:NSError? = nil
//		let url = fileCache.cachedUrl(file:file)
//		do {
//			try contents.write(to: url, atomically: true, encoding: String.Encoding.utf8)
//		} catch let err as NSError? {
//			os_log("error saving file %{public}@: %{public}@", type:.error, file.description, err!)
//			error = err
//		}
//		completionHandler(error)
//	}
//}
