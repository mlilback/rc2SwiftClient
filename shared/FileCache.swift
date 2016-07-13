//
//  FileCache.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import BrightFutures

enum FileCacheError: ErrorType {
	case FailedToCreateURL(file:File)
	case DownloadAlreadyInProgress
}

protocol FileCache {
	var fileManager:FileManager { get }

	func isFileCached(file:File) -> Bool
	func flushCacheForWorkspace(wspace:Workspace)
	///recaches the specified file if it has changed
	func flushCacheForFile(file:File) -> NSProgress?
	///caches all the files in the workspace that aren't already cached with the current version of the file
	//observer fractionCompleted on returned progress for completion handling
	func cacheAllFiles(setupHandler:((NSProgress)-> Void)) -> NSProgress?
	///returns the file system url where the file is/will be stored
	func cachedFileUrl(file:File) -> NSURL
}

//MARK: FileCache implementation

public class DefaultFileCache: NSObject, FileCache, NSURLSessionDownloadDelegate {
	var fileManager:FileManager
	private var baseUrl:NSURL
	private let workspace:Workspace
	private let urlConfig:NSURLSessionConfiguration
	weak var appStatus:AppStatus?
	private(set) var currentProgress:NSProgress?
	private var urlSession:NSURLSession?
	private var tasks:[Int:DownloadTask] = [:] //key is task identifier
	private let taskLock: NSLock = NSLock()
	private var downloadingAllFiles:Bool = false
	
	lazy var fileCacheUrl: NSURL = { () -> NSURL in
		do {
			let cacheDir = try self.fileManager.URLForDirectory(.CachesDirectory, inDomain: .UserDomainMask, appropriateForURL: nil, create: true)
			let ourDir = cacheDir.URLByAppendingPathComponent(NSBundle.mainBundle().bundleIdentifier!, isDirectory:true)
			let fileDir = ourDir!.URLByAppendingPathComponent(self.workspace.uniqueId, isDirectory: true)
			if !fileDir!.checkResourceIsReachableAndReturnError(nil) {
				try self.fileManager.createDirectoryAtURL(fileDir!, withIntermediateDirectories: true, attributes: nil)
			}
			return fileDir!
		} catch let err {
			log.error("failed to create file cache dir:\(err)")
		}
		fatalError("failed to create file cache")
	}()
	
	init(workspace:Workspace, baseUrl:NSURL, config:NSURLSessionConfiguration, appStatus:AppStatus?=nil) {
		self.fileManager = NSFileManager.defaultManager()
		self.workspace = workspace
		self.baseUrl = baseUrl
		urlConfig = config
		self.appStatus = appStatus
		super.init()
	}
	
	deinit {
		urlSession?.invalidateAndCancel()
	}
	
	func downloadTaskWithFileId(fileId:Int) -> DownloadTask? {
		for aTask in tasks {
			if aTask.1.file.fileId == fileId { return aTask.1 }
		}
		return nil
	}
	
	func isFileCached(file:File) -> Bool {
		return cachedFileUrl(file).checkResourceIsReachableAndReturnError(nil)
	}

	func flushCacheForWorkspace(wspace:Workspace) {
		
	}
	
	///recaches the specified file if it has changed
	func flushCacheForFile(file:File) -> NSProgress? {
		if downloadingAllFiles {
			log.warning("flushCacheForFile called while all files are being downloaded")
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
			try fileManager.removeItemAtURL(cachedFileUrl(file))
		} catch let err as NSError {
			//don't care if doesn't exist
			if !(err.domain == NSCocoaErrorDomain && err.code == 4) {
				log.info("got err removing file in flushCacheForFile:\(err)")
			}
		}
		let task = DownloadTask(file: file, cache: self, parentProgress: nil)
		if currentProgress == nil { currentProgress = task.progress }
		tasks[task.task.taskIdentifier] = task
		//want to trigger next time through event loop
		dispatch_async(dispatch_get_main_queue()) {
			task.task.resume()
		}
		return task.progress
	}
	
	///caches all the files in the workspace that aren't already cached with the current version of the file
	//observer fractionCompleted on returned progress for completion handling
	func cacheAllFiles(setupHandler:((NSProgress)-> Void)) -> NSProgress? {
		if downloadingAllFiles {
			log.warning("cacheAllFiles called while already in progress")
			return nil
		}
		taskLock.lock()
		defer { taskLock.unlock() }
		if tasks.count > 0 {
			log.warning("cacheAllFiles called with tasks in progress")
			return nil
		}
		if nil == urlSession {
			prepareUrlSession()
		}
		currentProgress = NSProgress(totalUnitCount: Int64(workspace.files.count))
		for aFile in workspace.files {
			let theTask = DownloadTask(file: aFile, cache: self, parentProgress: currentProgress)
			tasks[theTask.task.taskIdentifier] = theTask
		}
		setupHandler(currentProgress!)
		//only start after all tasks are created
		dispatch_async(dispatch_get_main_queue()) {
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
	func cachedFileUrl(file:File) -> NSURL {
		let fileUrl = NSURL(fileURLWithPath: "\(file.fileId).\(file.fileType.fileExtension)", relativeToURL: fileCacheUrl).absoluteURL
		return fileUrl!
	}
	
	private func prepareUrlSession() {
		guard urlSession == nil else { return }
		let config = urlConfig
		if config.HTTPAdditionalHeaders == nil {
			config.HTTPAdditionalHeaders = [:]
		}
		config.HTTPAdditionalHeaders!["Accept"] = "application/octet-stream"
		self.urlSession = NSURLSession(configuration: config, delegate: self, delegateQueue: NSOperationQueue.mainQueue())
	}
	
	public func URLSession(session: NSURLSession, downloadTask: NSURLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64)
	{
		guard let task = tasks[downloadTask.taskIdentifier] else { fatalError("no cacheTask for task that thinks we are its delegate") }
		task.progress.completedUnitCount = totalBytesWritten
		if downloadingAllFiles {
			let per = Int(currentProgress!.fractionCompleted * 100)
			currentProgress!.localizedDescription = "Downloading files: %\(per) complete"
		}
	}
	
	public func URLSession(session: NSURLSession, task: NSURLSessionTask, didCompleteWithError error: NSError?)
	{
		taskLock.lock()
		defer { taskLock.unlock() }
		if downloadingAllFiles {
			if tasks.count > 1 {
				tasks.removeValueForKey(task.taskIdentifier)
				return
			}
			downloadingAllFiles = false
			tasks.removeAll()
		} else {
			guard let _ = tasks[task.taskIdentifier] else {
				fatalError("no DownloadTask for Session Task")
			}
			tasks.removeValueForKey(task.taskIdentifier)
		}
		currentProgress?.rc2_complete(error)
		dispatch_async(dispatch_get_main_queue()) {
			self.currentProgress = nil
		}
	}
	
	//called when a task has finished downloading a file
	public func URLSession(session: NSURLSession, downloadTask: NSURLSessionDownloadTask, didFinishDownloadingToURL location: NSURL)
	{
		taskLock.lock()
		defer { taskLock.unlock() }
		guard let cacheTask = tasks[downloadTask.taskIdentifier] else {
			fatalError("no DownloadTask for Session Task")
		}
		
		let cacheUrl = cachedFileUrl(cacheTask.file)
		if let status = (downloadTask.response as? NSHTTPURLResponse)?.statusCode where status == 304
		{
			cacheTask.progress.completedUnitCount = cacheTask.progress.totalUnitCount
			if downloadingAllFiles {
				return
			}
		}
		var p = Promise<NSURL?,FileError>()
		///move the file to the appropriate local cache url
		fileManager.moveTempFile(location, toUrl: cacheUrl, file: cacheTask.file, promise: &p)
		//wait for move to finish
		p.future.onSuccess() { _ in
			cacheTask.progress.completedUnitCount = cacheTask.progress.totalUnitCount
		}
	}
	
}

public class DownloadTask {
	weak var fileCache:DefaultFileCache?
	let file:File
	let task:NSURLSessionDownloadTask
	let progress:NSProgress
	let parent:NSProgress?
	
	init(file aFile:File, cache:DefaultFileCache, parentProgress:NSProgress?) {
		file = aFile
		fileCache = cache
		parent = parentProgress
		let fileUrl = NSURL(string: "workspaces/\(cache.workspace.wspaceId)/files/\(file.fileId)", relativeToURL: cache.baseUrl)!
		let request = NSMutableURLRequest(URL: fileUrl.absoluteURL!)
		let cacheUrl = cache.cachedFileUrl(file)
		if cacheUrl.checkResourceIsReachableAndReturnError(nil) {
			request.addValue("\"f/\(file.fileId)/\(file.version)\"", forHTTPHeaderField: "If-None-Match")
		}
		task = cache.urlSession!.downloadTaskWithRequest(request)
		if parentProgress != nil {
			progress = NSProgress(totalUnitCount: Int64(file.fileSize), parent: parentProgress!, pendingUnitCount: 1)
		} else {
			progress = NSProgress.discreteProgressWithTotalUnitCount(Int64(file.fileSize))
		}
	}
}

