//
//  FileImporter.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

/** represents a file to import along with the name to use for it (in case there already is a file with that name. If the name is nil, use the existing file name. */
struct FileToImport {
	var fileUrl: NSURL
	var uniqueFileName: String?
	init(url:NSURL, uniqueName:String?) {
		self.fileUrl = url
		self.uniqueFileName = uniqueName
	}
	var actualFileName:String { return (uniqueFileName == nil ? fileUrl.lastPathComponent : uniqueFileName)! }
}

/** interested parties should observer completeUnitCount on progress. When it equals totalUnitCount, the task is done. If there was an error, the error property will be set. Errors can be either one returned via the NSURLSession api or an error from the Rc2ErrorDomain.
*/
class FileImporter: NSObject, NSProgressReporting, NSURLSessionDataDelegate {
	dynamic var progress:NSProgress
	private var workspace:Workspace
	private var files:[FileToImport]
	private var uploadSession: NSURLSession!
	private var tasks:[Int:NSURLSessionUploadTask] = [:]
	private var childProgresses:[Int:NSProgress] = [:]
	private var tmpDir:NSURL
	private var completionHandler:(()->Void)
	
	/** designated initializer
		parameter files: the array of files to import
		parameter workspace: the workspace to import the files into
		urlSession: the session to use. Defaults to creating a new one using the config from RestServer
	*/
	init(_ files:[FileToImport], workspace:Workspace, configuration config:NSURLSessionConfiguration?, completionHandler:(()->Void))
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
		progress.rc2_addCompletionHandler() { [weak self] in
			log.info("complete progress")
			self?.completionHandler()
		}
		if myConfig == nil { myConfig = NSURLSessionConfiguration.defaultSessionConfiguration() }
		self.uploadSession = NSURLSession(configuration: myConfig!, delegate: self, delegateQueue: NSOperationQueue.mainQueue())
	}
	
	convenience init(_ files:[FileToImport], workspace:Workspace, completionHandler:(()->Void))
	{
		self.init(files, workspace:workspace, configuration:nil, completionHandler:completionHandler)
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
			tasks[index] = uploadSession.uploadTaskWithRequest(request, fromFile: srcUrl)
			childProgresses[index] = NSProgress(totalUnitCount: aFileToImport.fileUrl.fileSize())
			tasks[index]!.resume()
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
		let index:Int = tasks.filter {  $1 == task }.map { $0.0 }.first!
		guard let taskProgress = childProgresses[index] else {
			fatalError("failed to find progress for task of \(index)")
		}
		if let status = (task.response as? NSHTTPURLResponse)?.statusCode where status != 201 {
			let err = NSError(domain: Rc2ErrorDomain, code: Rc2ErrorCode.ServerError.rawValue, userInfo: [NSLocalizedDescriptionKey: NSHTTPURLResponse.localizedStringForStatusCode(status)])
			taskProgress.rc2_complete(err)
			self.completionHandler()
		} else {
			taskProgress.rc2_complete(nil)
			self.completionHandler()
		}
		tasks.removeValueForKey(index)
		childProgresses.removeValueForKey(index)
	}
	
	func URLSession(session: NSURLSession, task: NSURLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64)
	{
		log.info("session said sent data \(bytesSent)")
		let index:Int = tasks.filter {  $1 == task }.map { $0.0 }.first!
		guard let taskProgress = childProgresses[index] else {
			fatalError("failed to find progress for task of \(index)")
		}
		taskProgress.completedUnitCount = totalBytesSent
	}
}
