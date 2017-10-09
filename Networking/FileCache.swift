//
//  FileCache.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import ClientCore
import Foundation
import os
import ReactiveSwift
import Result
import Model

// this file is long because it has lots of helpers that need to be fileprivate
// swiftlint:disable file_length

public enum FileCacheError: Error, Rc2DomainError {
	case failedToCreateURL(file: AppFile)
	case downloadAlreadyInProgress
	case downloadError(urlError: Error)
	case fileError(FileError)
	case fileUpdateFailed(Error)
	case unknownError(Error)
}

public protocol FileCache {
	var fileManager: Rc2FileManager { get }
	var workspace: AppWorkspace { get }

	func close()
	func isFileCached(_ file: AppFile) -> Bool
//	func flushCache(workspace:Workspace)
	//removes the cached file
	func flushCache(file: AppFile)
	///recaches the specified file if it has changed
	func recache(file: AppFile) -> SignalProducer<Double, Rc2Error>
	//recaches an array of files
	func flushCache(files: [AppFile]) -> SignalProducer<Double, Rc2Error>
	///caches all the files in the workspace that aren't already cached with the current version of the file
	func cacheAllFiles() -> SignalProducer<Double, Rc2Error>
	/// returns the file system url where the file is/will be stored
	func cachedUrl(file: AppFile) -> URL
	// returns the file url where the specified file is/will be stored
	func cachedUrl(file: File) throws -> URL
	///calls cachedUrl, but downloads the file if correct version is not cached on disk
	/// - Parameter file: the file whose url is desired
	/// - Returns: signal producer that returns the URL to the cached contents of file
	func validUrl(for file: AppFile) -> SignalProducer<URL, Rc2Error>
	/// get the contents of a file
	///
	/// - Parameter file: the file whose contents should be returned
	/// - Returns: a signal producer that returns the file data or an error
	func contents(of file: AppFile) -> SignalProducer<Data, Rc2Error>
	
	func handle(change: SessionResponse.FileChangedData) throws
	
	/// updates a file's contents on disk with the provided data
	///
	/// - Parameters:
	///   - file: the file whose contents changed
	///   - data: the data with the contents of the file
	/// - Returns: signal producer that signals completed or error
	func cache(file: File, withData data: Data) -> SignalProducer<Void, Rc2Error>
	
	/// "caches" a file with contents of a specified file
	///
	/// - Parameters:
	///   - file: the file whose contents changed
	///   - srcFile: the file whose contents should be used for file
	/// - Returns: signal producer that signals completed or error
	func cache(file: File, srcFile: URL) -> SignalProducer<Void, Rc2Error>

	/// saves file contents (does not update file object)
	///
	/// - Parameters:
	///   - file: the file to save data to
	///   - contents: the contents to save to the file
	/// - Returns: a signal producer that signals success or error
	func save(file: AppFile, contents: String) -> SignalProducer<Void, Rc2Error>
}

// MARK: FileCache implementation

fileprivate class DownloadTask {
	let file: AppFile
	let task: URLSessionDownloadTask
	var bytesDownloaded: Int = 0
	var partOfDownloadAll: Bool
	fileprivate var signal: Signal<Double, Rc2Error>
	fileprivate var observer: Signal<Double, Rc2Error>.Observer
	
	init(file aFile: AppFile, task: URLSessionDownloadTask, forAll: Bool = false)
	{
		file = aFile
		self.task = task
		let (sig, obs) = Signal<Double, Rc2Error>.pipe()
		signal = sig
		observer = obs
		self.partOfDownloadAll = forAll
	}
}

fileprivate struct DownloadAll {
	let signal: Signal<Double, Rc2Error>
	let observer: Signal<Double, Rc2Error>.Observer
	let totalSize: Int
	private var sizeDownloaded: Int = 0
	private var filesRemaining: Int = 0
	
	var completed: Bool { return filesRemaining < 1 }
	
	init(totalSize: Int, fileCount: Int) {
		let (sig, obs) = Signal<Double, Rc2Error>.pipe()
		signal = sig
		observer = obs
		self.totalSize = totalSize
		self.filesRemaining = fileCount
	}

	private func calculateAndSendProgress() {
		guard sizeDownloaded > 0 else { return }
		var val = Double(sizeDownloaded) / Double(totalSize)
		if !val.isFinite { val = 1.0 }
		observer.send(value: val)
	}
	
	mutating func adjust(completedTask: DownloadTask, error: Rc2Error? = nil) {
		guard completedTask.partOfDownloadAll else { return }
		guard filesRemaining > 0 else {
			os_log("adjust called too many times", log: .cache, type: .error)
			fatalError()
		}
		filesRemaining -= 1
		guard error == nil else {
			//TODO: should we send errors or not? i.e. with 10 files, if file 4 fails should we stop downloading 6-10?
			return
		}
		sizeDownloaded += completedTask.bytesDownloaded
		calculateAndSendProgress()
		//only continue if all files downloaded
		if filesRemaining == 0 {
			observer.sendCompleted()
		}
	}
}

public final class DefaultFileCache: NSObject, FileCache {
	// MARK: properties
	public let mainQueue: DispatchQueue
	public var fileManager: Rc2FileManager
	public let workspace: AppWorkspace
	fileprivate var baseUrl: URL
	fileprivate var urlSession: URLSession?
	fileprivate var tasks: [Int: DownloadTask] = [:] //key is task identifier
	fileprivate let saveQueue: DispatchQueue
	fileprivate let taskLockQueue: DispatchQueue
	fileprivate var downloadAll: DownloadAll?
	fileprivate var lastModTimes: [Int: TimeInterval] = [:]
	
	lazy var fileCacheUrl: URL = { () -> URL in
		do {
			return try AppInfo.subdirectory(type: .cachesDirectory, named: self.workspace.uniqueId)
		} catch {
			os_log("failed to create file cache: %{public}@", log: .cache, type: .error, error as NSError)
		}
		fatalError("failed to create file cache")
	}()
	
	// MARK: methods
	public init(workspace: AppWorkspace, baseUrl: URL, config: URLSessionConfiguration, fileManager: Rc2FileManager? = nil, queue: DispatchQueue = DispatchQueue.main)
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
	
	public func close() {
		urlSession?.invalidateAndCancel()
		urlSession = nil
	}
	
	public func isFileCached(_ file: AppFile) -> Bool {
		let url = cachedUrl(file: file)
		return url.fileExists() && url.fileSize() > 0
	}

//	@discardableResult public func flushCache(workspace:Workspace) {
//
//	}
	
	public func flushCache(file: AppFile) {
		self.taskLockQueue.sync {
			guard self.downloadTaskWithFileId(file.fileId) == nil else {
				//download already in progress. no need to erase
				return
			}
			if let mtime = self.lastModTimes[file.fileId] {
				let timediff = Date.timeIntervalSinceReferenceDate - mtime
				if timediff < 0.5 {
					os_log("skipping flush because too recent", log: .cache, type: .info)
					return
				}
			}
			os_log("flushing file %d", log: .cache, type: .info, file.fileId)
			self.removeFile(fileUrl: self.cachedUrl(file: file))
		}
	}
	
	///recaches the specified file if it has changed
	public func recache(file: AppFile) -> SignalProducer<Double, Rc2Error> {
		os_log("recache of %d started", log: .cache, type: .debug, file.fileId)
		var producer: SignalProducer<Double, Rc2Error>?
		self.taskLockQueue.sync {
			if let fileTask = self.downloadTaskWithFileId(file.fileId) {
				//download in progress, return a producer that sends progress for the existing download
				producer = self.producer(signal: fileTask.signal)
				return
			}
			//download not in progress. remove currently cached file
			self.removeFile(fileUrl: self.cachedUrl(file: file))
			//create task and add observer to it
			let task = self.makeTask(file: file)
			self.tasks[task.task.taskIdentifier] = task
			//start task next time through event loop
			self.mainQueue.async {
				task.task.resume()
			}
			producer = self.producer(signal: task.signal)
		}
		return producer!
	}
	
	public func flushCache(files: [AppFile]) -> SignalProducer<Double, Rc2Error>
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
		let combinedProducer = SignalProducer< SignalProducer<Double, Rc2Error>, Rc2Error >(producers)
		return combinedProducer.flatten(.concat)
	}
	
	//caches all the files in the workspace that aren't already cached with the current version of the file
	public func cacheAllFiles() -> SignalProducer<Double, Rc2Error>
	{
		guard nil == downloadAll else {
			return producer(signal: self.downloadAll!.signal)
		}
		return SignalProducer<Double, Rc2Error> { observer, _ in
			self.taskLockQueue.sync {
				//if no files, completed
				if self.workspace.files.count < 1 {
					observer.sendCompleted()
					return
				}
				self.downloadAll = DownloadAll(totalSize: self.workspace.files.reduce(0) { $0 + $1.fileSize }, fileCount: self.workspace.files.count)
				_ = self.downloadAll?.signal.observe { event in
					switch event {
					case .value(let val):
						observer.send(value: val)
					case .completed:
						observer.sendCompleted()
					case .failed(let err):
						observer.send(error: err)
					case .interrupted:
						observer.sendInterrupted()
					}
				}
				//create tasks that don't already exist
				var createdTasks = [DownloadTask]()
				for aFile in self.workspace.files {
					var theTask = self.downloadTaskWithFileId(aFile.fileId)
					if nil == theTask {
						theTask = self.makeTask(file: aFile, partOfDownloadAll: true)
						self.tasks[theTask!.task.taskIdentifier] = theTask!
						createdTasks.append(theTask!)
					}
					theTask?.partOfDownloadAll = true
				}
				//start new tasks after all are created
				self.mainQueue.async {
					self.taskLockQueue.sync {
						createdTasks.forEach { $0.task.resume() }
					}
				}
			}
		}
	}
	
	//documentation in protocol
	public func validUrl(for file: AppFile) -> SignalProducer<URL, Rc2Error> {
		let url = cachedUrl(file: file)
		var producer: SignalProducer<URL, Rc2Error>?
		self.taskLockQueue.sync {
			if let dinfo = self.downloadAll {
				let sig = dinfo.signal.take(last: 1).map({ _ in return url })
				producer = SignalProducer<URL, Rc2Error>(sig)
			}
		}
		guard producer == nil else { return producer! }
		if isFileCached(file) {
			return SignalProducer<URL, Rc2Error>(value: url)
		}
		return recache(file: file)
			.map { _ in url }
	}
	
	///returns the file system url where the file is/will be stored
	public func cachedUrl(file: AppFile) -> URL {
		let fileUrl = URL(fileURLWithPath: "\(file.fileId).\(file.fileType.fileExtension)", relativeTo: fileCacheUrl).absoluteURL
		return fileUrl
	}

	///returns the file system url where the file is/will be stored
	public func cachedUrl(file: File) throws -> URL {
		guard let ftype = FileType.fileType(forFileName: file.name) else { throw NetworkingError.unsupportedFileType }
		let fileUrl = URL(fileURLWithPath: "\(file.id).\(ftype.fileExtension)", relativeTo: fileCacheUrl).absoluteURL
		return fileUrl
	}

	fileprivate func downloadTaskWithFileId(_ fileId: Int) -> DownloadTask? {
		for aTask in tasks where aTask.1.file.fileId == fileId {
			return aTask.1
		}
		return nil
	}
	
	fileprivate func makeTask(file: AppFile, partOfDownloadAll: Bool = false) -> DownloadTask {
//		let fileUrl = URL(string: "workspaces/\(workspace.wspaceId)/files/\(file.fileId)", relativeTo: baseUrl)!
		let fileUrl = URL(string: "file/\(file.fileId)", relativeTo: baseUrl)!
		var request = URLRequest(url: fileUrl.absoluteURL)
		let cacheUrl = cachedUrl(file: file)
		if (cacheUrl as NSURL).checkResourceIsReachableAndReturnError(nil) {
			request.addValue("\"\(file.eTag)\"", forHTTPHeaderField: "If-None-Match")
		}
		let dtask = urlSession!.downloadTask(with: request)
		os_log("creating download task for %d", log: .cache, type: .info, file.fileId)
		return DownloadTask(file: file, task: dtask, forAll: partOfDownloadAll)
	}
	
	/// removes file via fileManager, ignoring errors but logging them
	fileprivate func removeFile(fileUrl: URL) {
		do {
			try self.fileManager.removeItem(at: fileUrl)
		} catch let error as Rc2Error {
			guard error.type == .file, let nserr = error.nestedError as NSError?, nserr.domain == NSCocoaErrorDomain && nserr.code == 4 else {
				os_log("got err removing file in recache: %{public}@", log: .cache, type:.info, error.nestedError!.localizedDescription)
				return
			}
			//don't care if doesn't exist
		} catch {
			os_log("got err removing file in recache: %{public}@", log: .cache, type:.info, error.localizedDescription)
		}
	}

	///returns a producer that forwards values/completed from our progress signal, converting an interrupted into completed.
	/// This is because signals send interrupted if they are already closed, but the caller expects a normal signal producer.
	func producer<E>(signal: Signal<Double, E>) -> SignalProducer<Double, Rc2Error> {
		var theProducer: SignalProducer<Double, Rc2Error>?
		var nestedObserver: Signal<Double, Rc2Error>.Observer?
		let obsClosure = { (cObserver: Signal<Double, Rc2Error>.Observer, disp: Lifetime?) in
			nestedObserver = cObserver
		}
		theProducer = SignalProducer<Double, Rc2Error>(obsClosure).on(started: {
			signal.observe { event in
				switch event {
				case .interrupted, .completed:
					nestedObserver?.sendCompleted()
				case .value(let val):
					nestedObserver?.send(value: val)
				default:
					break
				}
			}
		})
		return theProducer!
	}
}

// MARK: - FileHandling
extension DefaultFileCache {
	/// get the contents of a file
	///
	/// - Parameter file: the file whose contents should be returned
	/// - Returns: a signal producer that returns the file data or an error
	public func contents(of file: AppFile) -> SignalProducer<Data, Rc2Error> {
		return SignalProducer<Data, Rc2Error> { observer, _ in
			self.taskLockQueue.sync {
				if let dinfo = self.downloadAll {
					//download is in progress. wait until completed
					dinfo.signal.observeCompleted {
						self.loadContents(file: file, observer: observer)
					}
				} else {
					//want to release lock before loading the contents
					self.mainQueue.async {
						self.loadContents(file: file, observer: observer)
					}
					return
				}
			}
		}
	}
	
	/// loads the contents of a file and signals success or error on the observer
	///
	/// - Parameters:
	///   - file: the file to load contents of
	///   - observer: observer to signal data/completed or error
	private func loadContents(file: AppFile, observer: Signal<Data, Rc2Error>.Observer) {
		let fileUrl = cachedUrl(file: file)
		//for some unknown reason the cached file could be empty and cause a crash
		guard fileUrl.fileExists() && fileUrl.fileSize() > 0 else {
			self.recache(file: file).startWithResult { result in
				guard result.error == nil else {
					observer.send(error: result.error!)
					return
				}
				self.readDataFromFile(file: file, observer: observer)
			}
			return
		}
		readDataFromFile(file: file, observer: observer)
	}
	
	/// reads raw data of file from filesystem, sends along to observer
	private func readDataFromFile(file: AppFile, observer: Signal<Data, Rc2Error>.Observer) {
		do {
			let data = try Data(contentsOf: self.cachedUrl(file: file))
			observer.send(value: data)
		} catch {
			observer.send(error: Rc2Error(type: .cocoa, nested: error, explanation: "failed to load contents of file \(file.name)"))
		}
	}

	public func handle(change: SessionResponse.FileChangedData) throws {
		//TODO: implement
	}
	
	/// "caches" a file with provided data
	///
	/// - Parameters:
	///   - file: the file whose contents changed
	///   - data: the data with the contents of the file
	/// - Returns: signal producer that signals completed or error
	public func cache(file: File, withData data: Data) -> SignalProducer<Void, Rc2Error>
	{
		return SignalProducer<Void, Rc2Error> { observer, _ in
			do {
				let url = try self.cachedUrl(file: file)
				try data.write(to: url)
				observer.sendCompleted()
			} catch {
				observer.send(error: Rc2Error(type: .cocoa, nested: error, explanation: "failed to save \(file.name) to file cache"))
			}
			}.observe(on: QueueScheduler(targeting: self.mainQueue))
	}
	
	/// "caches" a file with contents of a specified file
	///
	/// - Parameters:
	///   - file: the file whose contents changed
	///   - srcFile: the file whose contents should be used for file
	/// - Returns: signal producer that signals completed or error
	public func cache(file: File, srcFile: URL) -> SignalProducer<Void, Rc2Error>
	{
		precondition(srcFile.fileExists())
		return SignalProducer<Void, Rc2Error> { observer, _ in
			do {
				let url = try self.cachedUrl(file: file)
				try self.fileManager.copyItem(at: srcFile, to: url)
				observer.sendCompleted()
			} catch {
				observer.send(error: Rc2Error(type: .cocoa, nested: error, explanation: "failed to save \(file.name) to file cache"))
			}
			}.observe(on: QueueScheduler(targeting: self.mainQueue))
	}
	
	/// saves file contents (does not update file object)
	///
	/// - Parameters:
	///   - file: the file to save data to
	///   - contents: the contents to save to the file
	/// - Returns: a signal producer that signals success or error
	public func save(file: AppFile, contents: String) -> SignalProducer<Void, Rc2Error> {
		return SignalProducer<Void, Rc2Error> { observer, _ in
			let url = self.cachedUrl(file: file)
			do {
				try contents.write(to: url, atomically: true, encoding: .utf8)
				observer.sendCompleted()
			} catch {
				observer.send(error: Rc2Error(type: .cocoa, nested: error, explanation: "failed to save \(file.name) to file cache"))
			}
		}.observe(on: QueueScheduler(targeting: self.mainQueue))
	}
}

// MARK: - URLSessionDownloadDelegate
extension DefaultFileCache: URLSessionDownloadDelegate {
	public func urlSession(_ session: URLSession, downloadTask urlTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64)
	{
		guard let task = tasks[urlTask.taskIdentifier] else {
			fatalError("no cacheTask for task that thinks we are its delegate")
		}
		task.bytesDownloaded = Int(totalBytesWritten)
//		downloadAll?.adjust(completedTask: task)
	}
	
	//called when a task is complete and the data has been saved
	public func urlSession(_ session: URLSession, task urlTask: URLSessionTask, didCompleteWithError error: Error?)
	{
		taskLockQueue.sync {
			guard let dloadTask = tasks[urlTask.taskIdentifier] else {
				os_log("unknown url task did complete", log: .cache, type: .error)
				return
			}
			var generatedError: Rc2Error?
			defer {
				self.downloadAll?.adjust(completedTask: dloadTask, error: generatedError)
				if self.downloadAll?.completed ?? false {
					self.downloadAll?.observer.sendCompleted()
					self.downloadAll = nil
				}
				self.lastModTimes[dloadTask.file.fileId] = Date.timeIntervalSinceReferenceDate
				self.tasks.removeValue(forKey: urlTask.taskIdentifier)
				if generatedError != nil {
					os_log("failure downloading file %d: %{public}@", log: .network, type: .error, dloadTask.file.fileId, generatedError!.errorDescription ?? "unknown")
					self.mainQueue.async { dloadTask.observer.send(error: generatedError!) }
				}
			}
			guard error == nil else {
				generatedError = Rc2Error(type: .network, nested: FileCacheError.downloadError(urlError: error!))
				return
			}
			//check for http error
			if let hresponse = urlTask.response?.httpResponse {
				if hresponse.statusCode >= 400 {
					generatedError = Rc2Error(type: .network, nested: NetworkingError.invalidHttpStatusCode(hresponse))
					return
				}
			}
			DispatchQueue.main.async {
				dloadTask.observer.send(value: 1.0)
				dloadTask.observer.sendCompleted()
				os_log("successfully downloaded file %d", log: .cache, type: .info, dloadTask.file.fileId)
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
			//TODO: does this make sense? make a unit test
			if let status = (downloadTask.response?.httpResponse)?.statusCode, status == 304 {
				cacheTask.bytesDownloaded = cacheTask.file.fileSize
			}
			///move the file to the appropriate local cache url
			guard let _ = try? fileManager.move(tempFile: location, to: cacheUrl, file: cacheTask.file) else {
				os_log("error moving downloaded file to final location %{public}@", log: .cache, cacheUrl.absoluteString)
				return
			}
		}
	}
}
