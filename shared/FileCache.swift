//
//  FileCache.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import BrightFutures
import os

enum FileCacheError: Error {
	case failedToCreateURL(file:File)
	case downloadAlreadyInProgress
}

protocol FileCache {
	var fileManager:Rc2FileManager { get }

	func isFileCached(_ file:File) -> Bool
	func flushCache(workspace:Workspace)
	///recaches the specified file if it has changed
	@discardableResult func flushCache(file:File) -> Progress?
	///caches all the files in the workspace that aren't already cached with the current version of the file
	//observer fractionCompleted on returned progress for completion handling
	@discardableResult func cacheAllFiles(_ setupHandler:((Progress)-> Void)) -> Progress?
	///returns the file system url where the file is/will be stored
	func cachedUrl(file:File) -> URL
}

//MARK: FileCache implementation

open class DefaultFileCache: NSObject, FileCache, URLSessionDownloadDelegate {
	var fileManager:Rc2FileManager
	fileprivate var baseUrl:URL
	fileprivate let workspace:Workspace
	fileprivate let urlConfig:URLSessionConfiguration
	weak var appStatus:AppStatus?
	fileprivate(set) var currentProgress:Progress?
	fileprivate var urlSession:Foundation.URLSession?
	fileprivate var tasks:[Int:DownloadTask] = [:] //key is task identifier
	fileprivate let taskLock: NSLock = NSLock()
	fileprivate var downloadingAllFiles:Bool = false
	
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
			os_log("failed to create file cache (%{public}@) dir: %{public}@", type:.error, fileDir!.path, err)
		}
		fatalError("failed to create file cache")
	}()
	
	init(workspace:Workspace, baseUrl:URL, config:URLSessionConfiguration, appStatus:AppStatus?=nil, fileManager:Rc2FileManager? = nil)
	{
		if fileManager != nil {
			self.fileManager = fileManager!
		} else {
			self.fileManager = Rc2DefaultFileManager()
		}
		self.workspace = workspace
		self.baseUrl = baseUrl
		urlConfig = config
		self.appStatus = appStatus
		super.init()
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
	@discardableResult func flushCache(file:File) -> Progress? {
		if downloadingAllFiles {
			os_log("flushCacheForFile called while all files are being downloaded")
			return nil
		}
		taskLock.lock()
		defer { taskLock.unlock() }
		if downloadTaskWithFileId(file.fileId) != nil {
			//download already in progress. should we cancel it and start again? maybe if a large file?
			return nil
		}
		if nil == urlSession {
			prepareUrlSession()
		}
		do {
			try fileManager.removeItem(at:cachedUrl(file:file))
		} catch let err as NSError {
			//don't care if doesn't exist
			if !(err.domain == NSCocoaErrorDomain && err.code == 4) {
				os_log("got err removing file in flushCacheForFile: %@", type:.info, err)
			}
		}
		let task = DownloadTask(file: file, cache: self, parentProgress: nil)
		if currentProgress == nil { currentProgress = task.progress }
		tasks[task.task.taskIdentifier] = task
		//want to trigger next time through event loop
		DispatchQueue.main.async {
			task.task.resume()
		}
		return task.progress
	}
	
	///caches all the files in the workspace that aren't already cached with the current version of the file
	//observer fractionCompleted on returned progress for completion handling
	/// - parameter setupHandler: called once all download tasks are created, but before they are resumed
	/// if the progress parameter is nil, caching was not necessary
	@discardableResult func cacheAllFiles(_ setupHandler:((Progress)-> Void)) -> Progress? {
		let promise = Promise<Progress?, NSError>()
		precondition(!downloadingAllFiles)
		taskLock.lock()
		defer { taskLock.unlock() }
		assert(tasks.count == 0)
		if nil == urlSession {
			prepareUrlSession()
		}
		currentProgress = Progress(totalUnitCount: Int64(workspace.files.count))
		if workspace.files.count < 1 {
			//if no files to cache, fire off progress complete on next iteration of main loop
			DispatchQueue.main.async {
				self.currentProgress?.rc2_complete(nil)
			}
			return currentProgress
		}
		for aFile in workspace.files {
			let theTask = DownloadTask(file: aFile, cache: self, parentProgress: currentProgress)
			tasks[theTask.task.taskIdentifier] = theTask
		}
		setupHandler(currentProgress!)
		//only start after all tasks are created
		DispatchQueue.main.async {
			self.taskLock.lock()
			defer { self.taskLock.unlock() }
			for aTask in self.tasks.values {
				aTask.task.resume()
			}
		}
 		downloadingAllFiles = true
		return currentProgress
	}
	
	///returns the file system url where the file is/will be stored
	func cachedUrl(file:File) -> URL {
		let fileUrl = URL(fileURLWithPath: "\(file.fileId).\(file.fileType.fileExtension)", relativeTo: fileCacheUrl).absoluteURL
		return fileUrl
	}
	
	fileprivate func prepareUrlSession() {
		guard urlSession == nil else { return }
		let config = urlConfig
		if config.httpAdditionalHeaders == nil {
			config.httpAdditionalHeaders = [:]
		}
		config.httpAdditionalHeaders!["Accept"] = "application/octet-stream"
		self.urlSession = Foundation.URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue.main)
	}
	
	open func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64)
	{
		guard let task = tasks[downloadTask.taskIdentifier] else { fatalError("no cacheTask for task that thinks we are its delegate") }
		task.progress.completedUnitCount = totalBytesWritten
		if downloadingAllFiles {
			let per = Int(currentProgress!.fractionCompleted * 100)
			currentProgress!.localizedDescription = "Downloading files: %\(per) complete"
		}
	}
	
	open func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?)
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
		currentProgress?.rc2_complete(error)
		DispatchQueue.main.async {
			self.currentProgress = nil
		}
	}
	
	//called when a task has finished downloading a file
	open func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL)
	{
		taskLock.lock()
		defer { taskLock.unlock() }
		guard let cacheTask = tasks[downloadTask.taskIdentifier] else {
			fatalError("no DownloadTask for Session Task")
		}
		
		let cacheUrl = cachedUrl(file:cacheTask.file)
		if let status = (downloadTask.response as? HTTPURLResponse)?.statusCode , status == 304
		{
			cacheTask.progress.completedUnitCount = cacheTask.progress.totalUnitCount
			if downloadingAllFiles {
				return
			}
		}
		var p = Promise<URL?,FileError>()
		///move the file to the appropriate local cache url
		fileManager.move(tempFile: location, to: cacheUrl, file: cacheTask.file, promise: &p)
		//wait for move to finish
		p.future.onSuccess() { _ in
			cacheTask.progress.completedUnitCount = cacheTask.progress.totalUnitCount
		}
	}
	
}

open class DownloadTask {
	weak var fileCache:DefaultFileCache?
	let file:File
	let task:URLSessionDownloadTask
	let progress:Progress
	let parent:Progress?
	
	init(file aFile:File, cache:DefaultFileCache, parentProgress:Progress?) {
		file = aFile
		fileCache = cache
		parent = parentProgress
		let fileUrl = URL(string: "workspaces/\(cache.workspace.wspaceId)/files/\(file.fileId)", relativeTo: cache.baseUrl)!
		var request = URLRequest(url: fileUrl.absoluteURL)
		let cacheUrl = cache.cachedUrl(file:file)
		if (cacheUrl as NSURL).checkResourceIsReachableAndReturnError(nil) {
			request.addValue("\"f/\(file.fileId)/\(file.version)\"", forHTTPHeaderField: "If-None-Match")
		}
		task = cache.urlSession!.downloadTask(with: request)
		if parentProgress != nil {
			progress = Progress(totalUnitCount: Int64(file.fileSize), parent: parentProgress!, pendingUnitCount: 1)
		} else {
			progress = Progress.discreteProgress(totalUnitCount: Int64(file.fileSize))
		}
	}
}

