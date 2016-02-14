//
//  DefaultSessionFileHandler.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import BrightFutures

class DefaultSessionFileHandler: SessionFileHandler, FileCacheDownloadDelegate {
	var workspace:Workspace
	let fileCache:FileCache
	weak var fileDelegate:SessionFileHandlerDelegate?
	private(set) var filesLoaded:Bool = false
	private var downloadPromise: Promise <Bool,FileError>
	
	init(wspace:Workspace) {
		self.workspace = wspace
		self.fileCache = FileCache()
		self.downloadPromise = Promise<Bool,FileError>()
	}
	
	func loadFiles() {
		do  {
			downloadPromise = Promise<Bool,FileError>()
			try fileCache.cacheFilesForWorkspace(workspace, delegate: self)
		} catch {
			//TODO: inform caller that already in progress
			log.error("loadFiles called while load already in progress")
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
					p.failure(self.downloadPromise.future.error!)
				}
			}.onFailure() { err in
				p.failure(err)
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
	
	///called as bytes are recieved over the network
	func fileCache(cache:FileCache, updatedProgressWithStatus progress:FileCacheDownloadStatus) {
		
	}
	
	///called when all the files have been downloaded and cached
	func fileCacheDidFinishDownload(cache:FileCache, workspace:Workspace) {
		fileDelegate?.filesLoaded()
		filesLoaded = true
		downloadPromise.success(true)
	}
	
	///called on error. The download is canceled and fileCacheDidFinishDownload is not called
	func fileCache(cache:FileCache, failedToDownload file:File, error:ErrorType) {
		log.error("error loading file \(file.name): \(error)")
		downloadPromise.failure(.FailedToDownload)
	}

}
