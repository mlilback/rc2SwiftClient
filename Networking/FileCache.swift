//
//  FileCache.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import os
import ClientCore
import ReactiveSwift
import Result

enum FileCacheError: Error {
	case failedToCreateURL(file: File)
	case downloadAlreadyInProgress
	case downloadError(urlError: Error)
}

protocol FileCache {
	var fileManager:Rc2FileManager { get }

	func isFileCached(_ file:File) -> Bool
	func flushCache(workspace:Workspace)
	///recaches the specified file if it has changed
	func flushCache(file:File) -> SignalProducer<Double, FileCacheError>
	///caches all the files in the workspace that aren't already cached with the current version of the file
	//observer fractionCompleted on returned progress for completion handling
	func cacheAllFiles() -> SignalProducer<Double, FileCacheError>
	///returns the file system url where the file is/will be stored
	func cachedUrl(file:File) -> URL
}

//MARK: FileCache implementation

public final class DefaultFileCache: NSObject, FileCache, URLSessionDownloadDelegate {
	//MARK: properties
	var fileManager:Rc2FileManager
	fileprivate var baseUrl:URL
	fileprivate let workspace:Workspace
	fileprivate var urlSession:URLSession?
	fileprivate var tasks:[Int:DownloadTask] = [:] //key is task identifier
	fileprivate let taskLock: NSLock = NSLock()
	fileprivate var downloadingAllFiles:Bool = false
	///if downloadingAllFiles, the size of all files being downloaded
	fileprivate var totalDownloadSize: Int = 0
	///observer for current download all signal
	fileprivate var observer: Signal<Double, FileCacheError>.Observer?
	///disposable for current download all signal
	fileprivate var disposable: Disposable?
	
	lazy var fileCacheUrl: URL = { () -> URL in
		var fileDir: URL? = nil
		do {
			let cacheDir = try self.fileManager.Url(for:.cachesDirectory, domain: .userDomainMask, appropriateFor: nil, create: true)
			let ourDir = cacheDir.appendingPathComponent(Bundle.main.bundleIdentifier!, isDirectory:true)
			fileDir = ourDir.appendingPathComponent(self.workspace.uniqueId, isDirectory: true)
			if !fileDir!.fileExists() {
				try self.fileManager.createDirectoryHierarchy(at: fileDir!)
			}
			return fileDir!
		} catch let err as NSError {
			os_log("failed to create file cache (%{public}s) dir: %{public}s", type:.error, fileDir!.path, err)
		}
		fatalError("failed to create file cache")
	}()
	
	//MARK: methods
	init(workspace:Workspace, baseUrl:URL, config:URLSessionConfiguration, /*appStatus:AppStatus?=nil, */ fileManager:Rc2FileManager? = nil)
	{
		if fileManager != nil {
			self.fileManager = fileManager!
		} else {
			self.fileManager = Rc2DefaultFileManager()
		}
		self.workspace = workspace
		self.baseUrl = baseUrl
		super.init()
		let myConfig = config
		if myConfig.httpAdditionalHeaders == nil {
			myConfig.httpAdditionalHeaders = [:]
		}
		myConfig.httpAdditionalHeaders!["Accept"] = "application/octet-stream"
		urlSession = URLSession(configuration: myConfig, delegate: self, delegateQueue: OperationQueue.main)
	}
	
	deinit {
		urlSession?.invalidateAndCancel()
	}
	
	func downloadTaskWithFileId(_ fileId:Int) -> DownloadTask? {
		for aTask in tasks {
			if aTask.1.file.fileId == fileId { return aTask.1 }
		}
		return nil
	}
	
	func isFileCached(_ file:File) -> Bool {
		return cachedUrl(file:file).fileExists()
	}

	@discardableResult func flushCache(workspace:Workspace) {
		
	}
	
	///recaches the specified file if it has changed
	func flushCache(file:File) -> SignalProducer<Double, FileCacheError> {
		return SignalProducer<Double, FileCacheError>() { observer, disposable in
			guard !self.downloadingAllFiles else {
				observer.send(error: .downloadAlreadyInProgress)
				return
			}
			self.taskLock.lock()
			defer { self.taskLock.unlock() }
			guard self.downloadTaskWithFileId(file.fileId) == nil else {
				//download already in progress. should we cancel it and start again? maybe if a large file?
				observer.send(error: .downloadAlreadyInProgress)
				return
			}
			do {
				try self.fileManager.removeItem(at:self.cachedUrl(file:file))
			} catch let err as NSError {
				//don't care if doesn't exist
				if !(err.domain == NSCocoaErrorDomain && err.code == 4) {
					os_log("got err removing file in flushCacheForFile: %@", type:.info, err)
				}
			}
			
			self.observer = observer
			self.disposable = disposable
			let task = DownloadTask(file: file, cache: self)
			self.tasks[task.task.taskIdentifier] = task
			//start task next time through event loop
			DispatchQueue.main.async {
				task.task.resume()
			}
		}
	}
	
	///caches all the files in the workspace that aren't already cached with the current version of the file
	//observer fractionCompleted on returned progress for completion handling
	/// - parameter setupHandler: called once all download tasks are created, but before they are resumed
	/// if the progress parameter is nil, caching was not necessary
	func cacheAllFiles() -> SignalProducer<Double, FileCacheError>
	{
		precondition(!downloadingAllFiles)
		assert(tasks.count == 0)
		return SignalProducer<Double, FileCacheError>() { observer, disposable in
			self.taskLock.lock()
			defer { self.taskLock.unlock() }
			assert(self.tasks.count == 0)
			if self.workspace.files.count < 1 {
				observer.sendCompleted()
				return
			}
			self.totalDownloadSize = self.workspace.files.reduce(0) { $0 + $1.fileSize }
			for aFile in self.workspace.files {
				let theTask = DownloadTask(file: aFile, cache: self)
				self.tasks[theTask.task.taskIdentifier] = theTask
			}
			//only start after all tasks are created
			DispatchQueue.main.async {
				self.taskLock.lock()
				defer { self.taskLock.unlock() }
				self.tasks.forEach { $0.value.task.resume() }
			}
			self.downloadingAllFiles = true
		}
	}
	
	///returns the file system url where the file is/will be stored
	func cachedUrl(file:File) -> URL {
		let fileUrl = URL(fileURLWithPath: "\(file.fileId).\(file.fileType.fileExtension)", relativeTo: fileCacheUrl).absoluteURL
		return fileUrl
	}
	
	func calculateAndSendProgress() {
		let progress = tasks.reduce(0) { (result, tuple) in return result + tuple.value.bytesDownloaded }
		observer?.send(value: Double(progress) / Double(totalDownloadSize))
	}
	
	public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64)
	{
		guard let task = tasks[downloadTask.taskIdentifier] else {
			fatalError("no cacheTask for task that thinks we are its delegate")
		}
		task.bytesDownloaded = Int(totalBytesWritten)
		calculateAndSendProgress()
	}
	
	public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?)
	{
		taskLock.lock()
		defer { taskLock.unlock() }
		if downloadingAllFiles {
			if tasks.count > 1 {
				tasks.removeValue(forKey: task.taskIdentifier)
				return
			}
			downloadingAllFiles = false
			tasks.removeAll()
		} else {
			guard let _ = tasks[task.taskIdentifier] else {
				fatalError("no DownloadTask for Session Task")
			}
			tasks.removeValue(forKey: task.taskIdentifier)
		}
		defer {
			observer = nil
			disposable = nil
		}
		guard error == nil else {
			observer?.send(error: .downloadError(urlError: error!))
			return
		}
		observer?.sendCompleted()
	}
	
	//called when a task has finished downloading a file
	public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL)
	{
		taskLock.lock()
		defer { taskLock.unlock() }
		guard let cacheTask = tasks[downloadTask.taskIdentifier] else {
			fatalError("no DownloadTask for Session Task")
		}
		
		let cacheUrl = cachedUrl(file:cacheTask.file)
		if let status = (downloadTask.response as? HTTPURLResponse)?.statusCode , status == 304
		{
			cacheTask.bytesDownloaded = cacheTask.file.fileSize
			if downloadingAllFiles {
				return
			}
		}
		///move the file to the appropriate local cache url
		guard let _ = try? fileManager.move(tempFile: location, to: cacheUrl, file: cacheTask.file) else {
			os_log("error moving downloaded file to final location %{public}s", cacheUrl.absoluteString)
			return
		}
	}
	
}

class DownloadTask {
	weak var fileCache:DefaultFileCache?
	let file:File
	let task:URLSessionDownloadTask
	var bytesDownloaded: Int = 0
	
	init(file aFile:File, cache:DefaultFileCache)
	{
		file = aFile
		fileCache = cache
		let fileUrl = URL(string: "workspaces/\(cache.workspace.wspaceId)/files/\(file.fileId)", relativeTo: cache.baseUrl)!
		var request = URLRequest(url: fileUrl.absoluteURL)
		let cacheUrl = cache.cachedUrl(file:file)
		if (cacheUrl as NSURL).checkResourceIsReachableAndReturnError(nil) {
			request.addValue("\"f/\(file.fileId)/\(file.version)\"", forHTTPHeaderField: "If-None-Match")
		}
		task = cache.urlSession!.downloadTask(with: request)
	}
}

