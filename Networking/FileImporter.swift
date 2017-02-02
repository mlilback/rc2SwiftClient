//
//  FileImporter.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import ClientCore
import Freddy
import ReactiveSwift
import os

/// FINISH: not properly handlind multiple task progress, compeltion when all tasks are finished
/// need unit tests with multiple uploads

extension OSLog {
	static let importer: OSLog = OSLog(subsystem: AppInfo.bundleIdentifier, category: "import")
}


public class FileImporter: NSObject {
	public typealias ProgressSignalProducer = SignalProducer<ImportProgress, Rc2Error>
	
	public let fileCache: FileCache
	public var workspace: Workspace { return fileCache.workspace }
	/// array of files that were imported. Only available after the import is completed
	public fileprivate(set) var importedFiles: [File]
	fileprivate let files: [FileToImport]
	fileprivate var uploadSession: URLSession!
	fileprivate var tasks: [Int: ImportData] = [:]
	fileprivate var tmpDir: URL
	fileprivate let conInfo: ConnectionInfo
	let totalSize: Int
	let queue: DispatchQueue
	fileprivate var progressObserver: Signal<ImportProgress, Rc2Error>.Observer?
	fileprivate var progressDisposable: Disposable?
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
	public init(_ files:[FileToImport], fileCache: FileCache, connectInfo: ConnectionInfo, queue: DispatchQueue = .main, fileManager: FileManager = FileManager()) throws
	{
		self.files = files
		self.fileCache = fileCache
		self.conInfo = connectInfo
		self.queue = queue
		self.fileManager = fileManager
		self.importedFiles = []
		totalSize = files.reduce(0) { (size, fileInfo) -> Int in
			return size + Int(fileInfo.fileUrl.fileSize())
		}
		tmpDir = URL(fileURLWithPath: UUID().uuidString, relativeTo: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)).absoluteURL
		do {
			try fileManager.createDirectory(at: tmpDir, withIntermediateDirectories: true, attributes: [:])
		} catch {
			os_log("failed to create temporary directory for upload: %{public}@", log: .importer, type:.error, error.localizedDescription)
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
				try fileManager.linkItem(at: aFileToImport.fileUrl, to: srcUrl)
			} catch {
				os_log("failed to create link for upload: %{public}@", log: .importer, type:.error, error.localizedDescription)
				return ProgressSignalProducer(error: Rc2Error(type: .file, nested: error, explanation: ""))
			}
			let destUrl = URL(string: "/workspaces/\(workspace.wspaceId)/files/upload", relativeTo:baseUrl)!
			let request = NSMutableURLRequest(url: destUrl)
			request.httpMethod = "POST"
			request.setValue(aFileToImport.uniqueFileName, forHTTPHeaderField: "Rc2-Filename")
			request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
			request.setValue("application/json", forHTTPHeaderField: "Accept")
			let task = uploadSession.uploadTask(with: request as URLRequest, fromFile: srcUrl)
			tasks[index] = ImportData(task: task, srcFile: srcUrl)
		}
		return ProgressSignalProducer() { observer, disposable in
			self.progressObserver = observer
			self.progressDisposable = disposable
			self.queue.async {
				self.tasks.values.forEach { $0.task.resume() }
			}
		}
	}

	fileprivate func calculateAndSendProgress() {
		let progress = tasks.reduce(0) { (result, tuple) in return result + tuple.value.bytesDownloaded }
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
		var actualFileName:String { return (uniqueFileName == nil ? fileUrl.lastPathComponent : uniqueFileName)! }
	}

	struct ImportData {
		var task: URLSessionUploadTask
		var srcFile: URL
		var bytesDownloaded: Int = 0
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
		os_log("url session said complete", log: .importer, type:.info)
		defer {
			do { try fileManager.removeItem(at: tmpDir) } catch {}
		}
		guard error == nil else {
			os_log("error uploading file %{public}@", log: .importer, type:.error, (error as NSError?)!)
			progressObserver?.send(error: Rc2Error(type: .network, nested: NetworkingError.uploadFailed(error!)))
			return
		}
		guard let index: Int = tasks.filter({  $1.task == task }).map({ $0.0 }).first,
			let importData = tasks[index] else
		{
			fatalError("failed to find task info for import file")
		}
		defer { tasks.removeValue(forKey: index) }
		let httpResponse = task.response as! HTTPURLResponse
		os_log("upload status=%d", log: .importer, type:.info, httpResponse.statusCode)
		guard httpResponse.statusCode == 201 else {
			progressObserver?.send(error: Rc2Error(type: .network, nested: NetworkingError.invalidHttpStatusCode(httpResponse)))
			return
		}
		do {
			let json = try JSON(data: importData.data)
			var newFile = try File(json: json)
			newFile = try workspace.imported(file: newFile)
			let fileData = try Data(contentsOf: importData.srcFile)
			//is this really the best way to handle this error? oberver might have been set to nil
			fileCache.update(file: newFile, withData: fileData).startWithFailed { updateError in
				self.progressObserver?.send(error: updateError)
			}
			importedFiles.append(newFile)
		} catch let err as Rc2Error {
			progressObserver?.send(error: err)
		} catch {
			os_log("error updating file after rest confirmation: %{public}@", log: .importer, type:.error, error.localizedDescription)
			progressObserver?.send(error: Rc2Error(type: .updateFailed, nested: error))
		}
		if tasks.count == 1 { //deferred removal of current task
			os_log("file importer children done", log: .importer, type:.info)
			progressObserver?.sendCompleted()
			progressObserver = nil
			progressDisposable = nil
		}
	}
	
	public func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64)
	{
		os_log("session said sent data %d", log: .importer, type:.info, bytesSent)
		let index: Int = tasks.filter {  $1.task == task }.map { $0.0 }.first!
		guard tasks[index] != nil else {
			fatalError("failed to find progress for task of \(index)")
		}
		tasks[index]!.bytesDownloaded = Int(totalBytesSent)
		calculateAndSendProgress()
	}
	
	public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data)
	{
		os_log("session said received data %d", log: .importer, type:.info, data.count)
		let index:Int = tasks.filter {  $1.task == dataTask }.map { $0.0 }.first!
		guard tasks[index] != nil else {
			fatalError("failed to find progress for task of \(index)")
		}
		tasks[index]!.data.append(data)
	}
}
