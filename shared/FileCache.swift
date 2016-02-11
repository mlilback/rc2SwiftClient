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

//used to convey download progress to the delegate
struct FileCacheDownloadStatus {
	let totalItemCount:Int
	let itemsDownloadedCount:Int
	let currentFile:File?
	let percentComplete:Double

	init(itemCount:Int, downloadedCount:Int, currentFile:File?, complete:Double) {
		self.totalItemCount = itemCount
		self.itemsDownloadedCount = downloadedCount
		self.currentFile = currentFile
		self.percentComplete = complete
	}
}

protocol FileCacheDownloadDelegate {
	///called as bytes are recieved over the network
	func fileCache(cache:FileCache, updatedProgressWithStatus progress:FileCacheDownloadStatus)
	///called when all the files have been downloaded and cached
	func fileCacheDidFinishDownload(cache:FileCache, workspace:Workspace)
	///called on error. The download is canceled and fileCacheDidFinishDownload is not called
	func fileCache(cache:FileCache, failedToDownload file:File, error:ErrorType)
}

@objc class FileCacheDownloader: NSObject, NSURLSessionDownloadDelegate {
	let cache:FileCache
	let workspace:Workspace
	let delegate:FileCacheDownloadDelegate
	var urlSession:NSURLSession!
	var tasks:[NSURLSessionDownloadTask] = []
	var fileForTask:[Int:File] = [:]
	var totalBytes:Int = 0
	var bytesDownloaded:Int = 0
	var downloadedCount:Int = 0
	
	init(cache:FileCache, workspace wspace:Workspace, delegate:FileCacheDownloadDelegate) {
		self.cache = cache
		self.workspace = wspace
		self.delegate = delegate
		super.init()
	}
	
	deinit {
		urlSession.invalidateAndCancel()
	}
	
	func startDownload() throws {
		assert(tasks.count == 0, "FileCacheDownloader instance may only be used once")
		self.urlSession = NSURLSession(configuration: cache.restServer.urlConfig, delegate: self, delegateQueue: NSOperationQueue.mainQueue())
		for aFile in workspace.files {
			let fileUrl = NSURL(string: "workspaces/\(workspace.wspaceId)/files/\(aFile.fileId)", relativeToURL: cache.restServer.baseUrl)
			guard fileUrl != nil else {
				throw FileCacheError.FailedToCreateURL(file: aFile)
			}
			let aTask = urlSession.downloadTaskWithURL(fileUrl!.absoluteURL)
			tasks.append(aTask)
			fileForTask[aTask.taskIdentifier] = aFile
			totalBytes += aFile.fileSize
		}
		//only start after all tasks are created
		dispatch_async(dispatch_get_main_queue()) {
			_ = self.tasks.map({ task in task.resume() })
		}
	}
	
	func URLSession(session: NSURLSession, downloadTask: NSURLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64)
	{
		bytesDownloaded += Int(bytesWritten)
		let status = FileCacheDownloadStatus(itemCount: workspace.files.count, downloadedCount: downloadedCount, currentFile: fileForTask[downloadTask.taskIdentifier], complete: Double(bytesDownloaded) / Double(totalBytes))
		delegate.fileCache(cache, updatedProgressWithStatus: status)
	}
	
	func URLSession(session: NSURLSession, task: NSURLSessionTask, didCompleteWithError error: NSError?)
	{
		//if this is the last test we are waiting for, then the download is finished
		if tasks.count == 1 && tasks.contains(task as! NSURLSessionDownloadTask) {
			downloadFinished(task as! NSURLSessionDownloadTask, error: error)
		}
	}
	
	//called when a task has finished downloading a file
	func URLSession(session: NSURLSession, downloadTask: NSURLSessionDownloadTask, didFinishDownloadingToURL location: NSURL)
	{
		let file = fileForTask[downloadTask.taskIdentifier]
		var p = Promise<NSURL?,FileError>()
		///move the file to the appropriate local cache url
		cache.fileManager.moveTempFile(location, toUrl: cache.cachedFileUrl(file!), file: file, promise: &p)
		//wait for move to finish
		dispatch_async(dispatch_get_main_queue()) { () -> Void in
			p.future.onSuccess(callback: { (_) -> Void in
				if self.tasks.count > 1 {
					self.tasks.removeAtIndex(self.tasks.indexOf(downloadTask)!)
				}
			})
		}
	}
	
	func downloadFinished(task:NSURLSessionDownloadTask, error:NSError?) {
		assert(task == tasks.first, "last task is not the last task \(task.taskIdentifier) != \(self.tasks.first?.taskIdentifier)")
		self.tasks.removeAll()
		self.cache.downloaders.removeAtIndex(self.cache.downloaders.indexOf(self)!)
		urlSession.invalidateAndCancel()
		dispatch_async(dispatch_get_main_queue()) { () -> Void in
			if error != nil {
				self.delegate.fileCache(self.cache, failedToDownload: self.fileForTask[task.taskIdentifier]!, error: error!)
			} else {
				self.delegate.fileCacheDidFinishDownload(self.cache, workspace: self.workspace)
			}
			self.fileForTask.removeAll()
		}
	}
}

public class FileCache: NSObject {
	var fileManager:FileManager
	var restServer:RestServer
	var downloaders:[FileCacheDownloader] = []
	
	private lazy var urlSession:NSURLSession = {
		return NSURLSession(configuration: self.restServer.urlConfig)
	}()
	
	lazy var fileCacheUrl: NSURL = { () -> NSURL in
		do {
			let cacheDir = try self.fileManager.URLForDirectory(.CachesDirectory, inDomain: .UserDomainMask, appropriateForURL: nil, create: true)
			if !cacheDir.checkResourceIsReachableAndReturnError(nil) {
				try self.fileManager.createDirectoryAtURL(cacheDir, withIntermediateDirectories: true, attributes: nil)
			}
			return cacheDir
		} catch let err {
			log.error("failed to create file cache dir:\(err)")
		}
		fatalError("failed to create file cache")
	}()
	
	override init() {
		fileManager = NSFileManager.defaultManager()
		restServer = RestServer.sharedInstance
		super.init()
	}
	
	func isFileCached(file:File) -> Bool {
		return cachedFileUrl(file).checkResourceIsReachableAndReturnError(nil)
	}

	///caches all the files in the workspace that aren't already cached with the current version of the file
	/// notifies the delegate when complete
	func cacheFilesForWorkspace(wspace:Workspace, delegate:FileCacheDownloadDelegate) throws {
		if let _ = downloaders.indexOf({ $0.workspace.wspaceId == wspace.wspaceId }) {
			throw FileCacheError.DownloadAlreadyInProgress
		}
		let dloader = FileCacheDownloader(cache: self, workspace: wspace, delegate: delegate)
		downloaders.append(dloader)
		try dloader.startDownload()
	}
	
	func downloadFile(file:File, fromWorkspace wspace:Workspace) -> Future<NSURL?,FileError> {
		let p = Promise<NSURL?,FileError>()
		let cachedUrl = cachedFileUrl(file)
		if file.urlXAttributesMatch(cachedUrl) {
			p.success(cachedUrl)
			return p.future
		}
		let reqUrl = NSURL(string: "workspaces/\(wspace.wspaceId)/files/\(file.fileId)", relativeToURL: restServer.baseUrl)
		let req = NSMutableURLRequest(URL: reqUrl!)
		req.HTTPMethod = "GET"
		if cachedUrl.checkResourceIsReachableAndReturnError(nil) {
			req.addValue("f/\(file.fileId)/\(file.version)", forHTTPHeaderField: "If-None-Match")
		}
		req.addValue(file.fileType.mimeType, forHTTPHeaderField: "Accept")
		let task = urlSession.downloadTaskWithRequest(req) { (dloadUrl, response, error) -> Void in
			let hresponse = response as! NSHTTPURLResponse
			guard error == nil else { p.failure(.FileNotFound); return }
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
			default:
				p.failure(FileError.FileNotFound)
				break
			}
		}
		task.resume()
		return p.future
	}
	
	func cachedFileUrl(file:File) -> NSURL {
		let fileUrl = NSURL(fileURLWithPath: "\(file.fileId).\(file.fileType.fileExtension)", relativeToURL: fileCacheUrl)
		return fileUrl
	}
}

