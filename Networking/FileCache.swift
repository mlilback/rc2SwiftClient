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

extension OSLog {
	static let cache: OSLog = OSLog(subsystem: AppInfo.bundleIdentifier, category: "cache")
}

public enum FileCacheError: Error {
	case failedToCreateURL(file: File)
	case downloadAlreadyInProgress
	case downloadError(urlError: Error)
	case fileError(FileError)
	case fileUpdateFailed(CollectionNotifierError)
	case unknownError(Error)
}

public protocol FileCache {
	var fileManager: Rc2FileManager { get }
	var workspace: Workspace { get }

	func isFileCached(_ file:File) -> Bool
//	func flushCache(workspace:Workspace)
	//removes the cached file
	func flushCache(file: File)
	///recaches the specified file if it has changed
	func recache(file:File) -> SignalProducer<Double, Rc2Error>
	//recaches an array of files
	func flushCache(files: [File]) -> SignalProducer<Double, Rc2Error>
	///caches all the files in the workspace that aren't already cached with the current version of the file
	//observer fractionCompleted on returned progress for completion handling
	func cacheAllFiles() -> SignalProducer<Double, Rc2Error>
	///returns the file system url where the file is/will be stored
	func cachedUrl(file:File) -> URL
	/// get the contents of a file
	///
	/// - Parameter file: the file whose contents should be returned
	/// - Returns: a signal producer that returns the file data or an error
	func contents(of file: File) -> SignalProducer<Data, Rc2Error>
	
	/// updates a file's contents on disk (from the network). will update the workspace's file object
	///
	/// - Parameters:
	///   - file: the file whose contents changed
	///   - data: the data with the contents of the file
	/// - Returns: signal producer that signals completed or error
	func update(file: File, withData data: Data?) -> SignalProducer<Void, Rc2Error>
	
	/// saves file contents (does not update file object)
	///
	/// - Parameters:
	///   - file: the file to save data to
	///   - contents: the contents to save to the file
	/// - Returns: a signal producer that signals success or error
	func save(file: File, contents: String) -> SignalProducer<Void, Rc2Error>
}

//MARK: FileCache implementation

public final class DefaultFileCache: NSObject, FileCache {
	//MARK: properties
	public let mainQueue: DispatchQueue
	public var fileManager:Rc2FileManager
	public let workspace: Workspace
	fileprivate var baseUrl: URL
	fileprivate var urlSession: URLSession?
	fileprivate var tasks:[Int:DownloadTask] = [:] //key is task identifier
	fileprivate var downloadingAllFiles: Bool = false
	///if downloadingAllFiles, the size of all files being downloaded
	fileprivate var totalDownloadSize: Int = 0
	///observer for current download all signal
	fileprivate var observer: Signal<Double, Rc2Error>.Observer?
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
			os_log("failed to create file cache (%{public}s) dir: %{public}s", log: .cache, type: .error, fileDir!.path, err)
		}
		fatalError("failed to create file cache")
	}()
	
	//MARK: methods
	public init(workspace: Workspace, baseUrl: URL, config: URLSessionConfiguration, fileManager:Rc2FileManager? = nil, queue: DispatchQueue = DispatchQueue.main)
	{
		if fileManager != nil {
			self.fileManager = fileManager!
		} else {
			self.fileManager = Rc2DefaultFileManager()
		}
		self.mainQueue = queue
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
		urlSession = URLSession(configuration: myConfig, delegate: self, delegateQueue: nil)
	}
	
	deinit {
		urlSession?.invalidateAndCancel()
	}
	
	public func isFileCached(_ file:File) -> Bool {
		return cachedUrl(file:file).fileExists()
	}

//	@discardableResult public func flushCache(workspace:Workspace) {
//		
//	}
	
	public func flushCache(file: File) {
		self.taskLockQueue.sync {
			guard self.downloadTaskWithFileId(file.fileId) == nil else {
				//download already in progress. no need to erase
				return
			}
			do {
				try self.fileManager.removeItem(at:self.cachedUrl(file:file))
			} catch {
			}
		}
	}
	
	///recaches the specified file if it has changed
	public func recache(file:File) -> SignalProducer<Double, Rc2Error> {
		return SignalProducer<Double, Rc2Error>() { observer, disposable in
			guard !self.downloadingAllFiles else {
				observer.send(error: Rc2Error(type: .network, nested: FileCacheError.downloadAlreadyInProgress))
				return
			}
			self.taskLockQueue.sync {
				guard self.downloadTaskWithFileId(file.fileId) == nil else {
					//download already in progress. should we cancel it and start again? maybe if a large file?
					observer.send(error: Rc2Error(type: .network, nested: FileCacheError.downloadAlreadyInProgress))
					return
				}
				do {
					try self.fileManager.removeItem(at:self.cachedUrl(file:file))
				} catch let err as NSError {
					//don't care if doesn't exist
					if !(err.domain == NSCocoaErrorDomain && err.code == 4) {
						os_log("got err removing file in flushCacheForFile: %@", log: .cache, type:.info, err)
					}
				}
				
				self.observer = observer
				self.disposable = disposable
				let task = self.makeTask(file: file)
				self.tasks[task.task.taskIdentifier] = task
				//start task next time through event loop
				self.mainQueue.async {
					task.task.resume()
				}
			}
		}
	}
	
	public func flushCache(files: [File]) -> SignalProducer<Double, Rc2Error>
	{
		let sortedFiles = files.sorted { (f1, f2) in
			return f1.fileSize < f2.fileSize
		}
		let totalSize = sortedFiles.reduce(0) { $0 + $1.fileSize }
		var downloadedSize = 0
		var producers = [SignalProducer<Double, Rc2Error>]()
		sortedFiles.forEach { file in
			// create a producer that flushes the cache, mapping a single file's percent complete to the percent complete of all files and when finished, adding the size of that file to downloadedSize
			let producer = self.recache(file: file).map( { percentDone -> Double in
				guard percentDone.isFinite else { return Double(1) }
				let fdownloaded = Int(Double(file.fileSize) * percentDone)
				return Double(downloadedSize + fdownloaded) / Double(totalSize)
			}).on(completed: { 
				downloadedSize += file.fileSize
			})
			producers.append(producer)
		}
		//combine all the producers into a single producer of producers, and flatten the results into a single producer
		let combinedProducer = SignalProducer< SignalProducer<Double, Rc2Error>, Rc2Error >(values: producers)
		return combinedProducer.flatten(.concat).on(event: { (event) in
			print("got event: \(event)")
		})
	}
	
	///caches all the files in the workspace that aren't already cached with the current version of the file
	//observer fractionCompleted on returned progress for completion handling
	/// - parameter setupHandler: called once all download tasks are created, but before they are resumed
	/// if the progress parameter is nil, caching was not necessary
	public func cacheAllFiles() -> SignalProducer<Double, Rc2Error>
	{
		precondition(!downloadingAllFiles)
		assert(tasks.count == 0)
		return SignalProducer<Double, Rc2Error>() { observer, disposable in
			self.taskLockQueue.sync {
				assert(self.tasks.count == 0)
				if self.workspace.files.count < 1 {
					observer.sendCompleted()
					return
				}
				self.totalDownloadSize = self.workspace.files.reduce(0) { $0 + $1.fileSize }
				for aFile in self.workspace.files {
					let theTask = self.makeTask(file: aFile)
					self.tasks[theTask.task.taskIdentifier] = theTask
				}
				//prepare signal for success notification
				let (signal, sobserver) = Signal<Bool, NoError>.pipe()
				self.downloadInProgressSignal = signal
				self.downloadInProgressObserver = sobserver
				signal.observeResult { result in
					observer.send(value: 1.0)
					observer.sendCompleted()
				}
				//only start after all tasks are created
				self.mainQueue.async {
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
		var val = Double(progress) / Double(totalDownloadSize)
		if !val.isFinite { val = 1.0 }
		observer?.send(value: val)
	}
	
	func makeTask(file: File) -> DownloadTask {
		let fileUrl = URL(string: "workspaces/\(workspace.wspaceId)/files/\(file.fileId)", relativeTo: baseUrl)!
		var request = URLRequest(url: fileUrl.absoluteURL)
		let cacheUrl = cachedUrl(file: file)
		if (cacheUrl as NSURL).checkResourceIsReachableAndReturnError(nil) {
			request.addValue(file.eTag, forHTTPHeaderField: "If-None-Match")
		}
		let dtask = urlSession!.downloadTask(with: request)
		return DownloadTask(file: file, task: dtask)
	}
}

//MARK: - FileHandling
extension DefaultFileCache {
	/// get the contents of a file
	///
	/// - Parameter file: the file whose contents should be returned
	/// - Returns: a signal producer that returns the file data or an error
	public func contents(of file: File) -> SignalProducer<Data, Rc2Error> {
		return SignalProducer<Data, Rc2Error>() { observer, _ in
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
				self.mainQueue.async {
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
	private func loadContents(file: File, observer: Signal<Data, Rc2Error>.Observer) {
		do {
			let data = try Data(contentsOf: self.cachedUrl(file: file))
			observer.send(value: data)
		} catch {
			observer.send(error: Rc2Error(type: .cocoa, nested: error, explanation: "failed to load contents of file \(file.name)"))
		}
	}
	
	/// updates a file's contents on disk (from the network). will update the workspace's file object
	///
	/// - Parameters:
	///   - file: the file whose contents changed
	///   - data: the data with the contents of the file
	/// - Returns: signal producer that signals completed or error
	public func update(file: File, withData data: Data?) -> SignalProducer<Void, Rc2Error>
	{
		let updateSP = SignalProducer<Void, Rc2Error>() { observer, _ in
			do {
				try self.workspace.update(fileId: file.fileId, to: file)
				observer.sendCompleted()
			} catch let err as CollectionNotifierError {
				observer.send(error: Rc2Error(type: .updateFailed, nested: FileCacheError.fileUpdateFailed(err)))
			} catch {
				observer.send(error: Rc2Error(type: .unknown, nested: error))
			}
		}
		if let fileContents = data {
			return save(file: file, contents: String(data: fileContents, encoding: .utf8)!)
				.mapError({ ferr in
					return Rc2Error(type: .file, nested: ferr)
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
	public func save(file: File, contents: String) -> SignalProducer<Void, Rc2Error> {
		return SignalProducer<Void, Rc2Error> { observer, _ in
			let url = self.cachedUrl(file: file)
			self.saveQueue.async {
				do {
					try contents.write(to: url, atomically: true, encoding: .utf8)
					self.mainQueue.async {
						observer.sendCompleted()
					}
				} catch {
					self.mainQueue.async {
						observer.send(error: Rc2Error(type: .cocoa, nested: error, explanation: "failed to save \(file.name) to file cache"))
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
				self.mainQueue.async {
					self.observer?.send(value: 1.0)
				}
			}
			guard error == nil else {
				let rc2err = Rc2Error(type: .network, nested: FileCacheError.downloadError(urlError: error!))
				self.mainQueue.async { self.observer?.send(error: rc2err) }
				return
			}
			self.mainQueue.async {
				//need to nil out before sending completion otherwise if another download is in progress we'd nil out that task
				let obs = self.observer
				self.observer = nil
				self.disposable = nil
				obs?.sendCompleted()
			}
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
				os_log("error moving downloaded file to final location %{public}s", log: .cache, cacheUrl.absoluteString)
				return
			}
		}
	}
}

class DownloadTask {
	let file: File
	let task: URLSessionDownloadTask
	var bytesDownloaded: Int = 0
	
	init(file aFile: File, task: URLSessionDownloadTask)
	{
		file = aFile
		self.task = task
	}
}
