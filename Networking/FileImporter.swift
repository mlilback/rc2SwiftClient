//
//  FileImporter.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Rc2Common
import Foundation
import MJLLogger
import ReactiveSwift
import Model

/// FINISH: not properly handlind multiple task progress, compeltion when all tasks are finished
/// need unit tests with multiple uploads

public class FileImporter: NSObject {
	public typealias ProgressSignalProducer = SignalProducer<ImportProgress, Rc2Error>
	
	public let fileCache: FileCache
	public var workspace: AppWorkspace { return fileCache.workspace }
	/// array of files that were imported. Only available after the import is completed
	public fileprivate(set) var importedFileIds: Set<Int>
	fileprivate let files: [FileToImport]
	fileprivate var uploadSession: URLSession!
	fileprivate var tasks: [Int: ImportData] = [:]
	fileprivate var tmpDir: URL
	fileprivate let conInfo: ConnectionInfo
	let totalSize: Int
	let queue: DispatchQueue
	fileprivate var progressObserver: Signal<ImportProgress, Rc2Error>.Observer?
	fileprivate var progressLifetime: Lifetime?
	fileprivate let fileManager: FileManager
	
	/// Imports files to the server
	///
	/// - Parameters:
	///   - files: array of wrapped files to import
	///   - fileCache: the file cache to use for file system interaction
	///   - connectInfo: the server connection info
	///   - queue: the queue to send progress notifications on. defaults to main queue
	///   - fileManager: the file manager to use for caching files. defaults to FileManager()
	/// - Throws: .file with a nested error from fileManager
	public init(_ files: [FileToImport], fileCache: FileCache, connectInfo: ConnectionInfo, queue: DispatchQueue = .main, fileManager: FileManager = FileManager()) throws
	{
		self.files = files
		self.fileCache = fileCache
		self.conInfo = connectInfo
		self.queue = queue
		self.fileManager = fileManager
		self.importedFileIds = []
		totalSize = files.reduce(0) { (size, fileInfo) -> Int in
			return size + Int(fileInfo.fileUrl.fileSize())
		}
		tmpDir = URL(fileURLWithPath: UUID().uuidString, relativeTo: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)).absoluteURL
		do {
			try fileManager.createDirectory(at: tmpDir, withIntermediateDirectories: true, attributes: [:])
		} catch {
			Log.error("failed to create temporary directory for upload: \(error)", .network)
			throw Rc2Error(type: .file, nested: error)
		}
		super.init()
		self.uploadSession = URLSession(configuration: conInfo.urlSessionConfig, delegate: self, delegateQueue: nil)
	}
	
	public func producer() -> ProgressSignalProducer {
		precondition(progressObserver == nil)
		let baseUrl = conInfo.host.url!
		for (index, aFileToImport) in files.enumerated() {
			let srcUrl = tmpDir.appendingPathComponent(aFileToImport.actualFileName)
			do {
				// hard link to ignore user changes or deletion
				try fileManager.linkItem(at: aFileToImport.fileUrl, to: srcUrl)
			} catch {
				Log.error("failed to create link for upload: \(error)", .network)
				return ProgressSignalProducer(error: Rc2Error(type: .file, nested: error, explanation: ""))
			}
			// should url creation be done here? might be better elsewhere for reuse
			let destUrl = URL(string: "\(conInfo.host.urlPrefix)/file/\(workspace.wspaceId)", relativeTo: baseUrl)!
			var request = URLRequest(url: destUrl)
			request.httpMethod = "POST"
			request.setValue(conInfo.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
			request.setValue(aFileToImport.uniqueFileName, forHTTPHeaderField: "Rc2-Filename")
			request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
			request.setValue("application/json", forHTTPHeaderField: "Accept")
			let task = uploadSession.uploadTask(with: request, fromFile: srcUrl)
			tasks[index] = ImportData(task: task, srcFile: srcUrl)
		}
		return ProgressSignalProducer { observer, lifetime in
			self.progressObserver = observer
			self.progressLifetime = lifetime
			self.tasks.values.forEach { $0.task.resume() }
		}
	}

	fileprivate func calculateAndSendProgress() {
		let progress = tasks.reduce(0) { (result, tuple) in return result + tuple.value.bytesUploaded }
		var val = Double(progress) / Double(totalSize)
		if !val.isFinite { val = 1.0 }
		progressObserver?.send(value: ImportProgress(val, status: ""))
	}

	///represents a file to import along with the name to use for it (in case there already is a file with that name. If the name is nil, use the existing file name.
	public struct FileToImport {
		public private(set) var fileUrl: URL
		public private(set) var uniqueFileName: String?
		public init(url: URL, uniqueName: String?) {
			self.fileUrl = url
			self.uniqueFileName = uniqueName
			if nil == uniqueFileName {
				uniqueFileName = fileUrl.lastPathComponent
			}
		}
		var actualFileName: String { return (uniqueFileName == nil ? fileUrl.lastPathComponent : uniqueFileName)! }
	}

	struct ImportData {
		var task: URLSessionUploadTask
		var srcFile: URL
		var bytesUploaded: Int = 0
		var data: Data
		
		init(task: URLSessionUploadTask, srcFile: URL) {
			self.task = task
			self.srcFile = srcFile
			self.data = Data()
		}
	}

	public struct ImportProgress {
		public let percentComplete: Double
		public let status: String?
		
		init(_ percent: Double, status: String?) {
			let per = percent.isFinite ? percent : 1.0
			self.percentComplete = per
			self.status = status
		}
	}
}

extension FileImporter: URLSessionDataDelegate {
	public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?)
	{
		Log.info("url session said complete", .network)
		guard error == nil else {
			Log.error("error uploading file \(String(describing: error))", .network)
			progressObserver?.send(error: Rc2Error(type: .network, nested: NetworkingError.uploadFailed(error!)))
			return
		}
		guard let index: Int = tasks.filter({ $0.value.task == task }).map({ $0.key }).first,
			let importData = tasks[index] else
		{
			fatalError("failed to find task info for import file")
		}
		defer { tasks.removeValue(forKey: index) }
		guard let httpResponse = task.response?.httpResponse else { fatalError("impossible") }
		Log.info("upload status=\(httpResponse.statusCode)", .network)
		guard httpResponse.statusCode == 201 else {
			progressObserver?.send(error: Rc2Error(type: .network, nested: NetworkingError.invalidHttpStatusCode(httpResponse)))
			return
		}
		do {
			let rawFile: File = try conInfo.decode(data: importData.data)
			defer {
				importedFileIds.insert(rawFile.id)
			}
			// store the original file in the cache so it isn't immediately downloaded
			let fileData = try Data(contentsOf: importData.srcFile)
			//is this really the best way to handle this error? oberver might have been set to nil
			fileCache.cache(file: rawFile, withData: fileData).startWithFailed { updateError in
				self.progressObserver?.send(error: updateError)
			}
		} catch let err as Rc2Error {
			progressObserver?.send(error: err)
		} catch {
			Log.error("error updating file after rest confirmation: \(error)", .network)
			progressObserver?.send(error: Rc2Error(type: .updateFailed, nested: error))
		}
		if tasks.count == 1 { //deferred removal of current task
			Log.info("file importer children done", .network)
			progressObserver?.sendCompleted()
			progressObserver = nil
			progressLifetime = nil
			do { try fileManager.removeItem(at: tmpDir) } catch {}
		}
	}
	
	public func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64)
	{
		Log.info("session said sent data \(bytesSent)", .network)
		guard let index = tasks.filter({ $0.value.task == task }).map({ $0.key }).first, tasks[index] != nil else {
			fatalError("failed to find progress for task of \(task.taskIdentifier)")
		}
		tasks[index]!.bytesUploaded = Int(totalBytesSent)
		calculateAndSendProgress()
	}
	
	public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data)
	{
		Log.info("session said received data \(data.count)", .network)
		guard let index = tasks.filter({ $0.value.task == dataTask }).map({ $0.key }).first, tasks[index] != nil else {
			fatalError("failed to find progress for task of \(dataTask.taskIdentifier)")
		}
		tasks[index]!.data.append(data)
	}
}
