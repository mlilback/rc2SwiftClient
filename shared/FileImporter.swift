//
//  FileImporter.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import SwiftyJSON
import os

/** represents a file to import along with the name to use for it (in case there already is a file with that name. If the name is nil, use the existing file name. */
struct FileToImport {
	var fileUrl: URL
	var uniqueFileName: String?
	init(url:URL, uniqueName:String?) {
		self.fileUrl = url
		self.uniqueFileName = uniqueName
		if nil == uniqueFileName {
			uniqueFileName = fileUrl.lastPathComponent
		}
	}
	var actualFileName:String { return (uniqueFileName == nil ? fileUrl.lastPathComponent : uniqueFileName)! }
}

struct ImportData {
	var task:URLSessionUploadTask
	var srcFile:URL
	var progress:Progress
	var data:NSMutableData
	
	init(task:URLSessionUploadTask, srcFile:URL, progress:Progress) {
		self.task = task
		self.srcFile = srcFile
		self.progress = progress
		self.data = NSMutableData()
	}
}

/** interested parties should observe completeUnitCount on progress. When it equals totalUnitCount, the task is done. If there was an error, the error property will be set. Errors can be either one returned via the NSURLSession api or an error from the Rc2ErrorDomain.
*/
class FileImporter: NSObject, ProgressReporting, URLSessionDataDelegate {
	dynamic var progress:Progress
	fileprivate var fileHandler:SessionFileHandler
	fileprivate var files:[FileToImport]
	fileprivate var uploadSession: Foundation.URLSession!
	fileprivate var tasks:[Int:ImportData] = [:]
	fileprivate var tmpDir:URL
	fileprivate var baseUrl:URL
	///ultimately called from completion handler added to root NSProgress
	fileprivate var completionHandler:((Progress)->Void)
	
	/** designated initializer
		parameter files: the array of files to import
		parameter workspace: the workspace to import the files into
		urlSession: the session to use. Defaults to creating a new one using the config from RestServer
	*/
	init(_ files:[FileToImport], fileHandler:SessionFileHandler, baseUrl:URL, configuration config:URLSessionConfiguration?, completionHandler:@escaping ((_ progress:Progress)->Void))
	{
		self.files = files
		self.fileHandler = fileHandler
		self.baseUrl = baseUrl
		self.completionHandler = completionHandler
		var myConfig = config
		let totalFileSize:Int64 = files.map({ $0.fileUrl }).reduce(0) { (size, url) -> Int64 in
			return size + url.fileSize()
		}
		progress = Progress(totalUnitCount: totalFileSize)
		tmpDir = URL(fileURLWithPath: UUID().uuidString, relativeTo: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)).absoluteURL
		do {
			try Foundation.FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true, attributes: [:])
		} catch let err as NSError {
			os_log("failed to create temporary directory for upload: %@", type:.error, err)
		}
		super.init()
		progress.rc2_addCompletionHandler() {
			os_log("complete progress", type:.info)
			self.completionHandler(self.progress)
		}
		if myConfig == nil { myConfig = URLSessionConfiguration.default }
		self.uploadSession = Foundation.URLSession(configuration: myConfig!, delegate: self, delegateQueue: OperationQueue.main)
	}
	
	/** starts the import. To know when complete, observe progress.fractionComplete and is complete when >= 1.0  */
	func startImport() throws {
		let fm = Foundation.FileManager.default
		for (index, aFileToImport) in files.enumerated() {
			let srcUrl = tmpDir.appendingPathComponent(aFileToImport.actualFileName)
			do {
				try fm.linkItem(at: aFileToImport.fileUrl, to: srcUrl)
			} catch let err as NSError {
				os_log("failed to create link for upload: %@", type:.error, err)
				throw err
			}
			let destUrl = URL(string: "/workspaces/\(fileHandler.workspace.wspaceId)/files/upload", relativeTo:baseUrl)!
			let request = NSMutableURLRequest(url: destUrl)
			request.httpMethod = "POST"
			request.setValue(aFileToImport.uniqueFileName, forHTTPHeaderField: "Rc2-Filename")
			request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
			request.setValue("application/json", forHTTPHeaderField: "Accept")
			let task = uploadSession.uploadTask(with: request as URLRequest, fromFile: srcUrl)
			let cprogress = Progress(totalUnitCount: aFileToImport.fileUrl.fileSize())
			tasks[index] = ImportData(task: task, srcFile: srcUrl, progress: cprogress)
			progress.addChild(cprogress, withPendingUnitCount: cprogress.totalUnitCount)
			task.resume()
		}
	}
	
	func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?)
	{
		os_log("session said complete", type:.info)
		defer {
			do { try Foundation.FileManager.default.removeItem(at: tmpDir) } catch _ {}
		}
		if error != nil {
			os_log("error uploading file %@", type:.error, (error as? NSError)!)
			return
		}
		let index:Int = tasks.filter {  $1.task == task }.map { $0.0 }.first!
		guard let importData = tasks[index] else {
			fatalError("failed to find progress for task of \(index)")
		}
		os_log("upload status=", type:.info, ((task.response as? HTTPURLResponse)?.statusCode)!)
		if let status = (task.response as? HTTPURLResponse)?.statusCode , status != 201 {
			let err = NSError(domain: Rc2ErrorDomain, code: Rc2ErrorCode.serverError.rawValue, userInfo: [NSLocalizedDescriptionKey: HTTPURLResponse.localizedString(forStatusCode: status)])
			progress.rc2_complete(err)
		} else { //got a proper 201 status code
			let json = JSON(data:importData.data as Data)
			let newFile = File(json: json)
			do {
				let idata = try Data(contentsOf: importData.srcFile)
				fileHandler.updateFile(newFile, withData: idata)
			} catch let err {
				os_log("error importing file %@: %@", type:.error, newFile.name, err as NSError)
			}
			importData.progress.completedUnitCount = importData.progress.totalUnitCount
			importData.progress.rc2_complete(nil)
		}
		tasks.removeValue(forKey: index)
		if tasks.count < 1 {
			os_log("file importer children done", type:.info)
		}
	}
	
	func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64)
	{
		os_log("session said sent data %@", type:.info, bytesSent)
		let index:Int = tasks.filter {  $1.task == task }.map { $0.0 }.first!
		guard let importData = tasks[index] else {
			fatalError("failed to find progress for task of \(index)")
		}
		importData.progress.completedUnitCount = totalBytesSent
	}
	
	func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data)
	{
		os_log("session said received data %@", type:.info, data.count)
		let index:Int = tasks.filter {  $1.task == dataTask }.map { $0.0 }.first!
		guard let importData = tasks[index] else {
			fatalError("failed to find progress for task of \(index)")
		}
		importData.data.append(data)
	}
}
