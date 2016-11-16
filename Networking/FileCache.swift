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
import NotifyingCollection

public enum FileCacheError: Error {
	case failedToCreateURL(file: File)
	case downloadAlreadyInProgress
	case downloadError(urlError: Error)
	case fileError(FileError)
	case fileUpdateFailed(CollectionNotifierError)
	case unknownError(Error)
}

public protocol FileCache {
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
	/// get the contents of a file
	///
	/// - Parameter file: the file whose contents should be returned
	/// - Returns: a signal producer that returns the file data or an error
	func contents(of file: File) -> SignalProducer<Data, FileError>
	
	/// updates a file's contents on disk (from the network). will update the workspace's file object
	///
	/// - Parameters:
	///   - file: the file whose contents changed
	///   - data: the data with the contents of the file
	/// - Returns: signal producer that signals completed or error
	func update(file: File, withData data: Data?) -> SignalProducer<Void, FileCacheError>
	
	/// saves file contents (does not update file object)
	///
	/// - Parameters:
	///   - file: the file to save data to
	///   - contents: the contents to save to the file
	/// - Returns: a signal producer that signals success or error
	func save(file: File, contents: String) -> SignalProducer<Void, FileError>
}

//MARK: FileCache implementation

public final class DefaultFileCache: NSObject, FileCache {
	//MARK: properties
	public var fileManager:Rc2FileManager
	fileprivate var baseUrl: URL
	fileprivate let workspace: Workspace
	fileprivate var urlSession: URLSession?
	fileprivate var tasks:[Int:DownloadTask] = [:] //key is task identifier
	fileprivate var downloadingAllFiles: Bool = false
	///if downloadingAllFiles, the size of all files being downloaded
	fileprivate var totalDownloadSize: Int = 0
	///observer for current download all signal
	fileprivate var observer: Signal<Double, FileCacheError>.Observer?
	///disposable for current download all signal
	fileprivate var disposable: Disposable?
	///signal to know when downloading all files is complete
	fileprivate var downloadInProgressSignal: Signal<Bool, NoError>?
	fileprivate var downloadInProgressObserver: Signal<Bool, NoError>.Observer?
	fileprivate let saveQueue: DispatchQueue
	fileprivate let taskLockQueue: DispatchQueue
	
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
	public init(workspace: Workspace, baseUrl: URL, config: URLSessionConfiguration, fileManager:Rc2FileManager? = nil)
	{
		if fileManager != nil {
			self.fileManager = fileManager!
		} else {
			self.fileManager = Rc2DefaultFileManager()
		}
		self.workspace = workspace
		self.baseUrl = baseUrl
		self.saveQueue = DispatchQueue(label: "rc2.filecache.save.serial")
		self.taskLockQueue = DispatchQueue(label: "rc2.filecache.tasklock")
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
	
	public func isFileCached(_ file:File) -> Bool {
		return cachedUrl(file:file).fileExists()
	}

	@discardableResult public func flushCache(workspace:Workspace) {
		
	}
	
	///recaches the specified file if it has changed
	public func flushCache(file:File) -> SignalProducer<Double, FileCacheError> {
		return SignalProducer<Double, FileCacheError>() { observer, disposable in
			guard !self.downloadingAllFiles else {
				observer.send(error: .downloadAlreadyInProgress)
				return
			}
			self.taskLockQueue.sync {
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
	}
	
	///caches all the files in the workspace that aren't already cached with the current version of the file
	//observer fractionCompleted on returned progress for completion handling
	/// - parameter setupHandler: called once all download tasks are created, but before they are resumed
	/// if the progress parameter is nil, caching was not necessary
	public func cacheAllFiles() -> SignalProducer<Double, FileCacheError>
	{
		precondition(!downloadingAllFiles)
		assert(tasks.count == 0)
		return SignalProducer<Double, FileCacheError>() { observer, disposable in
			self.taskLockQueue.sync {
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
				//prepare signal for success notification
				let (signal, sobserver) = Signal<Bool, NoError>.pipe()
				self.downloadInProgressSignal = signal
				self.downloadInProgressObserver = sobserver
				//only start after all tasks are created
				DispatchQueue.main.async {
					self.taskLockQueue.sync {
						self.tasks.forEach { $0.value.task.resume() }
					}
				}
				self.downloadingAllFiles = true
			}
		}
	}
	
	///returns the file system url where the file is/will be stored
	public func cachedUrl(file:File) -> URL {
		let fileUrl = URL(fileURLWithPath: "\(file.fileId).\(file.fileType.fileExtension)", relativeTo: fileCacheUrl).absoluteURL
		return fileUrl
	}
	
	fileprivate func downloadTaskWithFileId(_ fileId:Int) -> DownloadTask? {
		for aTask in tasks {
			if aTask.1.file.fileId == fileId { return aTask.1 }
		}
		return nil
	}
	
	fileprivate func calculateAndSendProgress() {
		let progress = tasks.reduce(0) { (result, tuple) in return result + tuple.value.bytesDownloaded }
		observer?.send(value: Double(progress) / Double(totalDownloadSize))
	}
}

//MARK: - FileHandling
extension DefaultFileCache {
	/// get the contents of a file
	///
	/// - Parameter file: the file whose contents should be returned
	/// - Returns: a signal producer that returns the file data or an error
	public func contents(of file: File) -> SignalProducer<Data, FileError> {
		return SignalProducer<Data, FileError>() { observer, _ in
			self.taskLockQueue.sync {
				guard nil == self.downloadInProgressSignal else
				{
					//download is in progress. wait until completed. use ! because should not change while taskLock is locked
					_ = self.downloadInProgressSignal!.observeCompleted {
						self.loadContents(file: file, observer: observer)
					}
					return
				}
				//want to release lock before actually load the contents
				DispatchQueue.main.async {
					self.loadContents(file: file, observer: observer)
				}
			}
		}
	}
	
	/// loads the contents of a file and signals success or error on the observer
	///
	/// - Parameters:
	///   - file: the file to load contents of
	///   - observer: observer to signal data/completed or error
	private func loadContents(file: File, observer: Signal<Data, FileError>.Observer) {
		do {
			let data = try Data(contentsOf: self.cachedUrl(file: file))
			observer.send(value: data)
		} catch let err as NSError {
			observer.send(error: FileError.foundationError(error: err))
		}
	}
	
	/// updates a file's contents on disk (from the network). will update the workspace's file object
	///
	/// - Parameters:
	///   - file: the file whose contents changed
	///   - data: the data with the contents of the file
	/// - Returns: signal producer that signals completed or error
	public func update(file: File, withData data: Data?) -> SignalProducer<Void, FileCacheError>
	{
		let updateSP = SignalProducer<Void, FileCacheError>() { observer, _ in
			do {
				try self.workspace.update(fileId: file.fileId, to: file)
				observer.sendCompleted()
			} catch let err as CollectionNotifierError {
				observer.send(error: .fileUpdateFailed(err))
			} catch {
				observer.send(error: .unknownError(error))
			}
		}
		if let fileContents = data {
			return save(file: file, contents: String(data: fileContents, encoding: .utf8)!)
				.mapError({ ferr in
					return FileCacheError.fileError(ferr)
				}).concat(updateSP)
		}
		return updateSP
	}
	
	/// saves file contents (does not update file object)
	///
	/// - Parameters:
	///   - file: the file to save data to
	///   - contents: the contents to save to the file
	/// - Returns: a signal producer that signals success or error
	public func save(file: File, contents: String) -> SignalProducer<Void, FileError> {
		return SignalProducer<Void, FileError> { observer, _ in
			let url = self.cachedUrl(file: file)
			self.saveQueue.async {
				do {
					try contents.write(to: url, atomically: true, encoding: .utf8)
					DispatchQueue.main.async {
						observer.sendCompleted()
					}
				} catch let err as NSError {
					DispatchQueue.main.async {
						observer.send(error: FileError.foundationError(error: err))
					}
				}
			}
		}
	}
}

//MARK: - URLSessionDownloadDelegate
extension DefaultFileCache: URLSessionDownloadDelegate {
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
		taskLockQueue.sync {
			if downloadingAllFiles {
				if tasks.count > 1 {
					tasks.removeValue(forKey: task.taskIdentifier)
					return
				}
				downloadingAllFiles = false
				tasks.removeAll()
				downloadInProgressObserver?.send(value: true)
				downloadInProgressObserver?.sendCompleted()
				downloadInProgressObserver = nil
				downloadInProgressSignal = nil
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
	}
	
	//called when a task has finished downloading a file
	public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL)
	{
		taskLockQueue.sync {
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
}

//MARK: -
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
