//
//  FileImporter.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import SwiftyJSON

/** represents a file to import along with the name to use for it (in case there already is a file with that name. If the name is nil, use the existing file name. */
struct FileToImport {
	var fileUrl: NSURL
	var uniqueFileName: String?
	init(url:NSURL, uniqueName:String?) {
		self.fileUrl = url
		self.uniqueFileName = uniqueName
		if nil == uniqueFileName {
			uniqueFileName = fileUrl.lastPathComponent
		}
	}
	var actualFileName:String { return (uniqueFileName == nil ? fileUrl.lastPathComponent : uniqueFileName)! }
}

struct ImportData {
	var task:NSURLSessionUploadTask
	var srcFile:NSURL
	var progress:NSProgress
	var data:NSMutableData
	
	init(task:NSURLSessionUploadTask, srcFile:NSURL, progress:NSProgress) {
		self.task = task
		self.srcFile = srcFile
		self.progress = progress
		self.data = NSMutableData()
	}
}

/** interested parties should observe completeUnitCount on progress. When it equals totalUnitCount, the task is done. If there was an error, the error property will be set. Errors can be either one returned via the NSURLSession api or an error from the Rc2ErrorDomain.
*/
class FileImporter: NSObject, NSProgressReporting, NSURLSessionDataDelegate {
	dynamic var progress:NSProgress
	private var workspace:Workspace
	private var files:[FileToImport]
	private var uploadSession: NSURLSession!
	private var tasks:[Int:ImportData] = [:]
	private var tmpDir:NSURL
	///ultimately called from completion handler added to root NSProgress
	private var completionHandler:((NSProgress)->Void)
	
	/** designated initializer
		parameter files: the array of files to import
		parameter workspace: the workspace to import the files into
		urlSession: the session to use. Defaults to creating a new one using the config from RestServer
	*/
	init(_ files:[FileToImport], workspace:Workspace, configuration config:NSURLSessionConfiguration?, completionHandler:((progress:NSProgress)->Void))
	{
		self.files = files
		self.workspace = workspace
		self.completionHandler = completionHandler
		var myConfig = config
		let totalFileSize:Int64 = files.map({ $0.fileUrl }).reduce(0) { (size, url) -> Int64 in
			return size + url.fileSize()
		}
		progress = NSProgress(totalUnitCount: totalFileSize)
		tmpDir = NSURL(fileURLWithPath: NSUUID().UUIDString, relativeToURL: NSURL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)).absoluteURL
		do {
			try NSFileManager.defaultManager().createDirectoryAtURL(tmpDir, withIntermediateDirectories: true, attributes: [:])
		} catch let err {
			log.error("failed to create temporary directory for upload: \(err)")
		}
		super.init()
		progress.rc2_addCompletionHandler() {
			log.info("complete progress")
			self.completionHandler(self.progress)
		}
		if myConfig == nil { myConfig = NSURLSessionConfiguration.defaultSessionConfiguration() }
		self.uploadSession = NSURLSession(configuration: myConfig!, delegate: self, delegateQueue: NSOperationQueue.mainQueue())
	}
	
	/** starts the import. To know when complete, observe progress.fractionComplete and is complete when >= 1.0  */
	func startImport() throws {
		let fm = NSFileManager.defaultManager()
		for (index, aFileToImport) in files.enumerate() {
			let srcUrl = tmpDir.URLByAppendingPathComponent(aFileToImport.actualFileName)
			do {
				try fm.linkItemAtURL(aFileToImport.fileUrl, toURL: srcUrl)
			} catch let err {
				log.error("failed to create link for upload: \(err)")
				throw err
			}
			let destUrl = NSURL(string: "/workspaces/\(workspace.wspaceId)/files/upload", relativeToURL: RestServer.sharedInstance.baseUrl)!
			let request = NSMutableURLRequest(URL: destUrl)
			request.HTTPMethod = "POST"
			request.setValue(aFileToImport.uniqueFileName, forHTTPHeaderField: "Rc2-Filename")
			request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
			let task = uploadSession.uploadTaskWithRequest(request, fromFile: srcUrl)
			let cprogress = NSProgress(totalUnitCount: aFileToImport.fileUrl.fileSize())
			tasks[index] = ImportData(task: task, srcFile: srcUrl, progress: cprogress)
			progress.addChild(cprogress, withPendingUnitCount: cprogress.totalUnitCount)
			task.resume()
		}
	}
	
	func URLSession(session: NSURLSession, task: NSURLSessionTask, didCompleteWithError error: NSError?)
	{
		log.info("session said complete")
		do { try NSFileManager.defaultManager().removeItemAtURL(tmpDir) } catch _ {}
		if error != nil {
			log.error("error uploading file \(error)")
			return
		}
		let index:Int = tasks.filter {  $1.task == task }.map { $0.0 }.first!
		guard let importData = tasks[index] else {
			fatalError("failed to find progress for task of \(index)")
		}
		log.info("upload status=\((task.response as? NSHTTPURLResponse)?.statusCode)")
		if let status = (task.response as? NSHTTPURLResponse)?.statusCode where status != 201 {
			let err = NSError(domain: Rc2ErrorDomain, code: Rc2ErrorCode.ServerError.rawValue, userInfo: [NSLocalizedDescriptionKey: NSHTTPURLResponse.localizedStringForStatusCode(status)])
			progress.rc2_complete(err)
		} else { //got a proper 201 status code
			let json = JSON(data:importData.data)
			let newFile = File(json: json)
			workspace.insertFile(newFile, atIndex: workspace.fileCount)
			//TODO: need to move file from importData.srcUrl to the cache directory via FileCache and/or FileManager
			importData.progress.completedUnitCount = importData.progress.totalUnitCount
			importData.progress.rc2_complete(nil)
		}
		tasks.removeValueForKey(index)
		if tasks.count < 1 {
			log.info("children done")
		}
	}
	
	func URLSession(session: NSURLSession, task: NSURLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64)
	{
		log.info("session said sent data \(bytesSent)")
		let index:Int = tasks.filter {  $1.task == task }.map { $0.0 }.first!
		guard let importData = tasks[index] else {
			fatalError("failed to find progress for task of \(index)")
		}
		importData.progress.completedUnitCount = totalBytesSent
	}
	
	func URLSession(session: NSURLSession, dataTask: NSURLSessionDataTask, didReceiveData data: NSData)
	{
		log.info("session said received data \(data.length)")
		let index:Int = tasks.filter {  $1.task == dataTask }.map { $0.0 }.first!
		guard let importData = tasks[index] else {
			fatalError("failed to find progress for task of \(index)")
		}
		importData.data.appendData(data)
	}
}
