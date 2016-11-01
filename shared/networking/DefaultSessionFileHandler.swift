//
//  DefaultSessionFileHandler.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import BrightFutures
import os

class DefaultSessionFileHandler: SessionFileHandler {
	var workspace:Workspace
	let fileCache:FileCache
	weak var appStatus:AppStatus?
	var baseUrl:URL
	weak var fileDelegate:SessionFileHandlerDelegate?
	fileprivate(set) var filesLoaded:Bool = false
	fileprivate var downloadPromise: Promise <SessionFileHandler,NSError>
	fileprivate var saveQueue:DispatchQueue
	
	init(wspace:Workspace, baseUrl:URL, config:URLSessionConfiguration, appStatus:AppStatus?) {
		self.workspace = wspace
		self.appStatus = appStatus
		self.fileCache = DefaultFileCache(workspace: workspace, baseUrl: baseUrl, config: config, appStatus:appStatus)
		self.baseUrl = baseUrl
		self.downloadPromise = Promise<SessionFileHandler,NSError>()
		self.saveQueue = DispatchQueue(label: "fileHandlerSerial", attributes: [])
	}
	
	@discardableResult func loadFiles() -> Future<SessionFileHandler, NSError> {
		filesLoaded = false //can be called to cache any new files
		guard workspace.files.count > 0 else {
			downloadPromise.success(self)
			loadComplete()
			return downloadPromise.future
		}
		fileCache.cacheAllFiles() { (progress) in
			self.appStatus?.currentProgress = progress
			progress.rc2_addCompletionHandler() {
				if let error = progress.rc2_error {
					_ = self.downloadPromise.failure(error as NSError)
				} else {
					self.filesLoaded = true
					self.downloadPromise.success(self)
				}
				self.loadComplete()
			}
		}
		return downloadPromise.future
	}

	func contentsOfFile(_ file:File) -> Future<Data?,FileError> {
		let p = Promise<Data?,FileError>()
		if !filesLoaded {
			//still downloading
			downloadPromise.future.onSuccess {_ in 
				do {
					let data = try Data(contentsOf: self.fileCache.cachedUrl(file:file))
					p.success(data)
				} catch {
					p.failure(FileError.foundationError(error: self.downloadPromise.future.error!))
				}
			}.onFailure() { err in
				p.failure(FileError.foundationError(error: err))
			}
		} else {
			do {
				let data = try Data(contentsOf: fileCache.cachedUrl(file:file))
				p.success(data)
			} catch {
				p.failure(.readError)
			}
		}
		return p.future
	}
	
	///called when all the files have been downloaded and cached
	func loadComplete() {
		fileDelegate?.filesLoaded()
		filesLoaded = true
	}

	func updateFile(_ file:File, withData data:Data?) -> Progress? {
		defer {
			if let idx = workspace.indexOfFilePassingTest({ return $0.fileId == file.fileId }) {
				workspace.replaceFile(at:idx, withFile: file)
			} else {
				workspace.insertFile(file, at: workspace.fileCount)
			}
		}
		if let fileContents = data {
			do {
				try fileContents.write(to: fileCache.cachedUrl(file:file), options: [])
			} catch let err {
				os_log("failed to write file %d update: %{public}s", type:.error, file.fileId, err as NSError)
			}
		} else {
			//TODO: test that this works properly for large files
			if let prog = fileCache.flushCache(file:file) {
				self.appStatus?.currentProgress = prog
				return prog
			}
		}
		return nil
	}
	
	func handleFileUpdate(_ file:File, change:FileChangeType) {
		switch(change) {
		case .Update:
			if let idx = workspace.indexOfFilePassingTest({ return $0.fileId == file.fileId }) {
				workspace.replaceFile(at:idx, withFile: file)
				fileCache.flushCache(file:file)
			} else {
				os_log("got file update for non-existing file: %d", file.fileId)
			}
		case .Insert:
			//TODO: implement file insert handling
			break
		case .Delete:
			//TODO:  implement file deletion handling
			break
		}
	}

	//the following will add the save operation to a serial queue to be executed immediately
	func saveFile(_ file:File, contents:String, completionHandler:@escaping (NSError?) -> Void) {
		let url = fileCache.cachedUrl(file:file)
		saveQueue.async {
			do {
				try contents.write(to: url, atomically: true, encoding: String.Encoding.utf8)
				DispatchQueue.main.async {
					completionHandler(nil)
				}
			} catch let err as NSError {
				os_log("error saving file %{public}s:%{public}s", type:.error, file.name, err)
				DispatchQueue.main.async {
					completionHandler(err)
				}
			}
		}
	}

}
