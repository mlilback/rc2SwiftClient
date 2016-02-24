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

//MARK: FileCache implementation

public class FileCache: NSObject, NSURLSessionDownloadDelegate {
	var fileManager:FileManager
	var baseUrl:NSURL
	private let workspace:Workspace
	private let urlConfig:NSURLSessionConfiguration
	let appStatus:AppStatus?
	private(set) var currentProgress:NSProgress?
	private var urlSession:NSURLSession?

	lazy var fileCacheUrl: NSURL = { () -> NSURL in
		do {
			let cacheDir = try self.fileManager.URLForDirectory(.CachesDirectory, inDomain: .UserDomainMask, appropriateForURL: nil, create: true)
			let ourDir = cacheDir.URLByAppendingPathComponent(NSBundle.mainBundle().bundleIdentifier!, isDirectory:true)
			let fileDir = ourDir.URLByAppendingPathComponent("FileCache", isDirectory: true)
			if !fileDir.checkResourceIsReachableAndReturnError(nil) {
				try self.fileManager.createDirectoryAtURL(fileDir, withIntermediateDirectories: true, attributes: nil)
			}
			return fileDir
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
	
	func isFileCached(file:File) -> Bool {
		return cachedFileUrl(file).checkResourceIsReachableAndReturnError(nil)
	}

	func flushCacheForWorkspace(wspace:Workspace) {
		
	}
	
	///caches all the files in the workspace that aren't already cached with the current version of the file
	//observer fractionCompleted on returned progress for completion handling
	func cacheAllFiles(setupHandler:((NSProgress)-> Void)) -> NSProgress {
		guard currentProgress == nil else { return currentProgress! }
		prepareUrlSession()
		currentProgress = NSProgress(totalUnitCount: Int64(workspace.files.count))
		for aFile in workspace.files {
			let fileUrl = NSURL(string: "workspaces/\(workspace.wspaceId)/files/\(aFile.fileId)", relativeToURL: baseUrl)!
			let request = NSMutableURLRequest(URL: fileUrl.absoluteURL)
			let cacheUrl = cachedFileUrl(aFile)
			if cacheUrl.checkResourceIsReachableAndReturnError(nil) {
				request.addValue("\"f/\(aFile.fileId)/\(aFile.version)\"", forHTTPHeaderField: "If-None-Match")
			}
			let aTask = urlSession!.downloadTaskWithRequest(request)
			let aProgress = NSProgress(totalUnitCount: Int64(aFile.fileSize), parent: currentProgress!, pendingUnitCount: 1)
			tasks[aTask.taskIdentifier] = FileCacheTask(task: aTask, file:aFile, progress: aProgress)
		}
		setupHandler(currentProgress!)
		//only start after all tasks are created
		dispatch_async(dispatch_get_main_queue()) {
			for aTask in self.tasks.values {
				aTask.task.resume()
			}
		}
		return currentProgress!
	}
	
	func cachedFileUrl(file:File) -> NSURL {
		let fileUrl = NSURL(fileURLWithPath: "\(file.fileId).\(file.fileType.fileExtension)", relativeToURL: fileCacheUrl).absoluteURL
		return fileUrl
	}

	private var tasks:[Int:FileCacheTask] = [:]
	
	private func prepareUrlSession() {
		guard urlSession == nil else { return }
		let config = urlConfig
		if config.HTTPAdditionalHeaders == nil {
			config.HTTPAdditionalHeaders = [:]
		}
		config.HTTPAdditionalHeaders!["Accept"] = "application/octet-stream"
		self.urlSession = NSURLSession(configuration: config, delegate: self, delegateQueue: NSOperationQueue.mainQueue())
	}
	
	//TODO: switch to using NSProgress instead of Future
	func downloadFile(file:File) -> Future<NSURL?,FileError> {
		let p = Promise<NSURL?,FileError>()
		let cachedUrl = cachedFileUrl(file)
		if file.urlXAttributesMatch(cachedUrl) {
			p.success(cachedUrl)
			return p.future
		}
		prepareUrlSession()
		let reqUrl = NSURL(string: "workspaces/\(workspace.wspaceId)/files/\(file.fileId)", relativeToURL: baseUrl)
		let req = NSMutableURLRequest(URL: reqUrl!)
		req.HTTPMethod = "GET"
		if cachedUrl.checkResourceIsReachableAndReturnError(nil) {
			req.addValue("\"f/\(file.fileId)/\(file.version)\"", forHTTPHeaderField: "If-None-Match")
		}
		req.addValue(file.fileType.mimeType, forHTTPHeaderField: "Accept")
		let task = urlSession!.downloadTaskWithRequest(req) { (dloadUrl, response, error) -> Void in
			guard error == nil else { p.failure(.FileNotFound); return }
			let hresponse = response as! NSHTTPURLResponse
			switch (hresponse.statusCode) {
			case 304: //use existing
				p.success(cachedUrl)
			case 200: //dloaded it
				var movePromise = Promise<NSURL?,FileError>()
				self.fileManager.moveTempFile(dloadUrl!, toUrl: cachedUrl, file:file, promise: &movePromise)
				movePromise.future.onSuccess(callback: { (murl) -> Void in
					p.success(murl)
				}) .onFailure(callback: { (err) -> Void in
					p.failure(err)
				})
			case 401: //auth error, should never happen
				fatalError("auth not properly setup for fileCache download")
			default:
				log.error("got a \(hresponse.statusCode) response from server downloading a file")
				p.failure(FileError.FileNotFound)
				break
			}
		}
		task.resume()
		return p.future
	}

	public func URLSession(session: NSURLSession, downloadTask: NSURLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64)
	{
		guard let cacheTask = tasks[downloadTask.taskIdentifier] else { fatalError("no cacheTask for task that thinks we are its delegate") }
		cacheTask.progress.completedUnitCount = totalBytesWritten
		let per = Int(currentProgress!.fractionCompleted * 100)
		currentProgress!.localizedDescription = "Downloading files: %\(per) complete"
	}
	
	public func URLSession(session: NSURLSession, task: NSURLSessionTask, didCompleteWithError error: NSError?)
	{
		//if this is the last test we are waiting for, then the download is finished
		guard tasks.count == 1 else { return }
		guard let _ = tasks[task.taskIdentifier] else { return }
		self.tasks.removeAll()
		currentProgress!.rc2_complete(error)
	}
	
	//called when a task has finished downloading a file
	public func URLSession(session: NSURLSession, downloadTask: NSURLSessionDownloadTask, didFinishDownloadingToURL location: NSURL)
	{
		guard let cacheTask = tasks[downloadTask.taskIdentifier] else {
			fatalError("no cacheTask for task we're a delegate for")
		}
		
		let cacheUrl = cachedFileUrl(cacheTask.file)
		if let status = (downloadTask.response as? NSHTTPURLResponse)?.statusCode where status == 304
		{
			cacheTask.progress.completedUnitCount = cacheTask.progress.totalUnitCount
			//remove all tasks except the last one, which is needed in didCompleteWithError
			if self.tasks.count > 1 {
				self.tasks[downloadTask.taskIdentifier] = nil
			}
			return
		}
		var p = Promise<NSURL?,FileError>()
		///move the file to the appropriate local cache url
		fileManager.moveTempFile(location, toUrl: cacheUrl, file: cacheTask.file, promise: &p)
		//wait for move to finish
		p.future.onSuccess() { _ in
			cacheTask.progress.completedUnitCount = cacheTask.progress.totalUnitCount
			//remove all tasks except the last one, which is needed in didCompleteWithError
			if self.tasks.count > 1 {
				self.tasks[downloadTask.taskIdentifier] = nil
			}
		}
	}
	
}

struct FileCacheTask {
	let task:NSURLSessionDownloadTask
	let progress:NSProgress
	let file:File
	init(task:NSURLSessionDownloadTask, file:File, progress:NSProgress) {
		self.task = task
		self.file = file
		self.progress = progress
	}
}

