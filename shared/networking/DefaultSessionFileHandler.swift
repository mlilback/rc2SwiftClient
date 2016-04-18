//
//  DefaultSessionFileHandler.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import BrightFutures

class DefaultSessionFileHandler: SessionFileHandler {
	var workspace:Workspace
	let fileCache:FileCache
	let appStatus:AppStatus?
	var baseUrl:NSURL
	weak var fileDelegate:SessionFileHandlerDelegate?
	private(set) var filesLoaded:Bool = false
	private var downloadPromise: Promise <Bool,NSError>
	private var saveQueue:dispatch_queue_t
	
	init(wspace:Workspace, baseUrl:NSURL, config:NSURLSessionConfiguration, appStatus:AppStatus?) {
		self.workspace = wspace
		self.appStatus = appStatus
		self.fileCache = FileCache(workspace: workspace, baseUrl: baseUrl, config: config, appStatus:appStatus)
		self.baseUrl = baseUrl
		self.downloadPromise = Promise<Bool,NSError>()
		self.saveQueue = dispatch_queue_create("fileHandlerSerial", DISPATCH_QUEUE_SERIAL)
	}
	
	func loadFiles() {
		filesLoaded = false //can be called to cache any new files
		fileCache.cacheAllFiles() { (progress) in
			self.appStatus?.updateStatus(progress)
			progress.rc2_addCompletionHandler() {
				if let error = progress.rc2_error {
					self.downloadPromise.failure(error)
				} else {
					self.filesLoaded = true
					self.downloadPromise.success(true)
				}
				self.appStatus?.updateStatus(nil)
			}
		}
	}

	func contentsOfFile(file:File) -> Future<NSData?,FileError> {
		let p = Promise<NSData?,FileError>()
		if !filesLoaded {
			//still downloading
			downloadPromise.future.onSuccess { _ in
				if let data = NSData(contentsOfURL: self.fileCache.cachedFileUrl(file)) {
					p.success(data)
				} else {
					p.failure(FileError.FoundationError(error: self.downloadPromise.future.error!))
				}
			}.onFailure() { err in
				p.failure(FileError.FoundationError(error: err))
			}
		} else {
			if let data = NSData(contentsOfURL: fileCache.cachedFileUrl(file)) {
				p.success(data)
			} else {
				p.failure(.ReadError)
			}
		}
		return p.future
	}
	
	///called when all the files have been downloaded and cached
	func loadComplete() {
		fileDelegate?.filesLoaded()
		filesLoaded = true
		downloadPromise.success(true)
	}

	func updateFile(file:File, withData data:NSData?) -> NSProgress? {
		let idx = workspace.indexOfFilePassingTest() { (obj, idx, stop) -> Bool in
			return (obj as! File).fileId == file.fileId
		}
		if idx == NSNotFound { //insert
			workspace.insertFile(file, atIndex: workspace.fileCount)
		} else { //update
			workspace.replaceFileAtIndex(idx, withFile: file)
		}
		if let fileContents = data {
			do {
				try fileContents.writeToURL(fileCache.cachedFileUrl(file), options: [])
			} catch let err {
				log.error("failed to write file \(file.fileId) update: \(err)")
			}
		} else {
			//TODO: test that this works properly for large files
			if let prog = fileCache.flushCacheForFile(file) {
				appStatus?.updateStatus(prog)
				return prog
			}
		}
		return nil
	}
	
	func handleFileUpdate(file:File, change:FileChangeType) {
		switch(change) {
		case .Update:
			let idx = workspace.indexOfFilePassingTest() { (obj, idx, stop) -> Bool in
				return (obj as! File).fileId == file.fileId
			}
			guard idx != NSNotFound else {
				log.warning("got file update for non-existing file: \(file.fileId)")
				return
			}
			workspace.replaceFileAtIndex(idx, withFile: file)
			fileCache.flushCacheForFile(file)
		case .Insert:
			//TODO: implement file insert handling
			break
		case .Delete:
			//TODO:  implement file deletion handling
			break
		}
	}

	//the following will add the save operation to a serial queue to be executed immediately
	func saveFile(file:File, contents:String, completionHandler:(NSError?) -> Void) {
		let url = fileCache.cachedFileUrl(file)
		dispatch_async(saveQueue) {
			do {
				try contents.writeToURL(url, atomically: true, encoding: NSUTF8StringEncoding)
				dispatch_async(dispatch_get_main_queue()) {
					completionHandler(nil)
				}
			} catch let err as NSError? {
				log.error("error saving file \(file): \(err)")
				dispatch_async(dispatch_get_main_queue()) {
					completionHandler(err)
				}
			}
		}
	}

}
