//
//  RestServer.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import SwiftWebSocket
import BrightFutures
import Result
import SwiftyJSON

@objc public class RestServer : NSObject, NSURLSessionTaskDelegate {

	private let kServerHostKey = "ServerHostKey"
	
	//for dependency injection
	var fileManager:FileManager = NSFileManager.defaultManager()
	
	public typealias Rc2RestCompletionHandler = (success:Bool, results:Any?, error:NSError?) -> Void
	
	private(set) var urlConfig : NSURLSessionConfiguration!
	private var urlSession : NSURLSession!
	private(set) public var hosts : [ServerHost]
	private(set) public var selectedHost : ServerHost
	private(set) public var loginSession : LoginSession?
	private(set) var baseUrl : NSURL?
	private var userAgent: String
	weak var appStatus:AppStatus?
	private(set) var session:Session?

	var restHosts : [String] {
		get {
			let hmap = hosts.map({ $0.name })
			return hmap
		}
	}
	var connectionDescription : String {
		get {
			let login = loginSession?.currentUser.login
			let host = loginSession?.host
			if (host == "rc2") {
				return login!;
			}
			return "\(login)@\(host)"
		}
	}
	
	override init() {
		userAgent = "Rc2 iOSClient"
		#if os(OSX)
			userAgent = "Rc2 MacClient"
		#endif
		
		//load hosts info from resource file
		let hostFileUrl = NSBundle.mainBundle().URLForResource("RestHosts", withExtension: "json")
		assert(hostFileUrl != nil, "failed to get RestHosts.json URL")
		hosts = ServerHost.loadHosts(hostFileUrl!)
		selectedHost = hosts.first!
		super.init()
		urlConfig = NSURLSessionConfiguration.defaultSessionConfiguration()
		urlConfig.HTTPAdditionalHeaders = ["User-Agent": userAgent, "Accept": "application/json"]
		urlSession = NSURLSession(configuration: urlConfig, delegate: self, delegateQueue:NSOperationQueue.mainQueue())
		if let previousHostName = NSUserDefaults.standardUserDefaults().stringForKey(self.kServerHostKey) {
			selectHost(previousHostName)
		}
	}

	///give a hostname from hosts property, the list of last known workspace names
	func workspaceNamesForHostName(hostName:String, userName:String) -> [String] {
		let defaults = NSUserDefaults.standardUserDefaults()
		let key = "ws//\(hostName)//\(userName)"
		if let names = defaults.objectForKey(key) as? [String] where names.count > 0 {
			return names
		}
		return ["Default"]
	}
	
	private func createError(err:FileError, description:String) -> NSError {
		switch(err) {
			case .FoundationError(let nserror):
				return nserror
			default:
				return NSError(domain: Rc2ErrorDomain, code: 1, userInfo: [NSLocalizedDescriptionKey:NSLocalizedString(description, comment: "")])
		}
	}
	
	private func createError(code:Int, description:String) -> NSError {
		return NSError(domain: Rc2ErrorDomain, code: code, userInfo: [NSLocalizedDescriptionKey:NSLocalizedString(description, comment: "")])
	}
	
	private func request(path:String, method:String, jsonDict:NSDictionary) -> NSMutableURLRequest {
		let url = NSURL(string: path, relativeToURL: baseUrl)
		let request = NSMutableURLRequest(URL: url!)
		request.HTTPMethod = method
		if loginSession != nil {
			request.addValue(loginSession!.authToken, forHTTPHeaderField:"Rc2-Auth")
		}
		if (jsonDict.count > 0) {
			request.addValue("application/json", forHTTPHeaderField:"Content-Type")
			request.HTTPBody = try! NSJSONSerialization.dataWithJSONObject(jsonDict, options: [])
		}
		return request
	}
	
	func selectHost(hostName:String) {
		if let host = hosts.filter({ return $0.name == hostName }).first {
			selectedHost = host
			let hprotocol = host.secure ? "https" : "http"
			let hoststr = "\(hprotocol)://\(host.host):\(host.port)/"
			baseUrl = NSURL(string: hoststr)!
		}
	}
	
	func createSession(wspace:Workspace, appStatus:AppStatus) -> Session {
		let request = NSMutableURLRequest(URL: createWebsocketUrl(wspace.wspaceId))
		request.addValue(loginSession!.authToken, forHTTPHeaderField: "Rc2-Auth")
		request.addValue(userAgent, forHTTPHeaderField: "User-Agent")
		let ws = WebSocket()
		session = Session(wspace, source:ws, restServer:self, appStatus:appStatus, networkConfig:urlConfig, hostIdentifier: selectedHost.host)
		session!.open(request)
		return session!
	}
	
	func createWebsocketUrl(wspaceId:Int32) -> NSURL {
		let build = NSBundle(forClass: RestServer.self).infoDictionary!["CFBundleVersion"]!
		#if os(OSX)
			let client = "osx"
		#else
			let client = "ios"
		#endif
		let prot = selectedHost.secure ? "wss" : "ws"
		let urlStr = "\(prot)://\(selectedHost.host):\(selectedHost.port)/ws/\(wspaceId)?client=\(client)&build=\(build)"
		return NSURL(string: urlStr)!
	}
	
	public func login(login:String, password:String, handler:Rc2RestCompletionHandler) {
		assert(baseUrl != nil, "baseUrl not specified")
		let loginObj = LoginHandler(config: urlConfig, baseUrl: baseUrl!)
		loginObj.login(login, password:password) { (data, response, error) -> Void in
			guard error == nil else {
				let appError = self.createError(404, description: (error?.localizedDescription)!)
				dispatch_async(dispatch_get_main_queue(), { handler(success: false, results: nil, error: appError) })
				return
			}
			let json = JSON(data:data!)
			switch(response!.statusCode) {
				case 200:
					self.loginSession = LoginSession(json: json, host: self.selectedHost.name)
					//store list of workspace names for this session
//					let wspaceListKey = "ws//\(self.selectedHost.name)//\(login)"
//					NSUserDefaults.standardUserDefaults().setObject(self.loginSession!.workspaces.map() { $0.name }, forKey: wspaceListKey)
					//for anyone that copies our session config later, include the auth token
					self.urlConfig.HTTPAdditionalHeaders!["Rc2-Auth"] = self.loginSession!.authToken
					dispatch_async(dispatch_get_main_queue(), { handler(success: true, results: self.loginSession!, error: nil) })
					NSUserDefaults.standardUserDefaults().setObject(self.loginSession!.host, forKey: self.kServerHostKey)
				case 401:
					let error = self.createError(401, description: "Invalid login or password")
					log.verbose("got a \(response!.statusCode)")
					dispatch_async(dispatch_get_main_queue(), { handler(success: false, results: nil, error: error) })
				default:
					let error = self.createError(response!.statusCode, description: "")
					log.warning("got unknown status code: \(response!.statusCode)")
					dispatch_async(dispatch_get_main_queue(), { handler(success: false, results: nil, error: error) })
			}
		}
	}
	/*
	public func createWorkspace(wspaceName:String, handler:Rc2RestCompletionHandler) {
		let req = request("workspaces", method:"POST", jsonDict: ["name":wspaceName])
		let task = urlSession.dataTaskWithRequest(req) { (data, response, error) -> Void in
			let json = JSON(data:data!)
			let httpResponse = response as! NSHTTPURLResponse
			switch(httpResponse.statusCode) {
			case 200:
				let wspace = Workspace(json: json)
				var spaces = (self.loginSession?.workspaces)!
				spaces.append(wspace)
				self.loginSession?.workspaces = spaces
				dispatch_async(dispatch_get_main_queue(), { handler(success: true, results: wspace, error: nil) })
			case 422:
				let error = self.createError(422, description: "A workspace with that name already exists")
				log.warning("got duplicate error")
				dispatch_async(dispatch_get_main_queue(), { handler(success: false, results: nil, error: error) })
			default:
				let error = self.createError(httpResponse.statusCode, description: "")
				log.warning("got unknown error: \(httpResponse.statusCode)")
				dispatch_async(dispatch_get_main_queue(), { handler(success: false, results: nil, error: error) })
			}
		}
		task.resume()
	}

	public func renameWorkspace(wspace:Workspace, newName:String, handler:Rc2RestCompletionHandler) {
		let req = request("workspaces/\(wspace.wspaceId)", method:"PUT", jsonDict: ["name":newName, "id":Int(wspace.wspaceId)])
		let task = urlSession.dataTaskWithRequest(req) { (data, response, error) -> Void in
			let json = JSON(data!)
			let httpResponse = response as! NSHTTPURLResponse
			switch(httpResponse.statusCode) {
			case 200:
				let modWspace = Workspace(json: json)
				var spaces = (self.loginSession?.workspaces)!
				spaces[spaces.indexOf(wspace)!] = modWspace
				dispatch_async(dispatch_get_main_queue(), { handler(success: true, results: modWspace, error: nil) })
			default:
				let error = self.createError(httpResponse.statusCode, description: "")
				log.warning("got unknown error: \(httpResponse.statusCode)")
				dispatch_async(dispatch_get_main_queue(), { handler(success: false, results: nil, error: error) })
			}
		}
		task.resume()
	}

	
	public func deleteWorkspace(wspace:Workspace, handler:Rc2RestCompletionHandler) {
		let req = request("workspaces/\(wspace.wspaceId)", method:"DELETE", jsonDict: [:])
		let task = urlSession.dataTaskWithRequest(req) { (data, response, error) -> Void in
			let httpResponse = response as! NSHTTPURLResponse
			switch(httpResponse.statusCode) {
			case 204:
				self.loginSession?.workspaces.removeAtIndex((self.loginSession?.workspaces.indexOf(wspace))!)
				dispatch_async(dispatch_get_main_queue(), { handler(success: true, results: nil, error: nil) })
			default:
				let error = self.createError(httpResponse.statusCode, description: "")
				log.warning("got unknown error: \(httpResponse.statusCode)")
				dispatch_async(dispatch_get_main_queue(), { handler(success: false, results: nil, error: error) })
			}
		}
		task.resume()
	} */
	
	/// - parameter destination: the directory to save the image in, overwriting any existing file
	public func downloadImage(wspace:Workspace, imageId:Int, destination:NSURL, handler:Rc2RestCompletionHandler) {
		let req = request("workspaces/\(wspace.wspaceId)/images/\(imageId)", method:"GET", jsonDict:[:])
		let (task, f) = urlSession.downloadWithPromise(req)
		task.resume()
		f.onSuccess(Queue.main.context) { (dloadUrl, response) in
			let fileUrl = NSURL(fileURLWithPath: "\(imageId).png", isDirectory: false, relativeToURL: destination)
			do {
				if fileUrl.checkResourceIsReachableAndReturnError(nil) {
					try self.fileManager.removeItemAtURL(fileUrl)
				}
				try self.fileManager.moveItemAtURL(dloadUrl!, toURL: fileUrl)
				handler(success: true, results: fileUrl, error: nil)
			} catch let err as NSError {
				let error = self.createError(FileError.FailedToSaveFile, description: err.localizedDescription)
				handler(success: false, results: nil, error: error)
			}
		}.onFailure(Queue.main.context) { (error) in
			handler(success:false, results:nil, error:error)
		}
	}

	public func downloadFile(wspace:Workspace, file:File, to destDirUrl:NSURL) -> Future<NSURL?, FileError> {
		var p = Promise<NSURL?,FileError>()
		let cacheUrl = NSURL(fileURLWithPath: file.name, relativeToURL: destDirUrl)
		let req = request("workspaces/\(wspace.wspaceId)/files/\(file.fileId)", method: "GET", jsonDict: [:])
		if cacheUrl.checkResourceIsReachableAndReturnError(nil) {
			req.addValue("f/\(file.fileId)/\(file.version)", forHTTPHeaderField: "If-None-Match")
		}
		req.addValue(file.fileType.mimeType, forHTTPHeaderField: "Accept")
		let task = urlSession.downloadTaskWithRequest(req) { (dloadUrl, response, error) -> Void in
			let hresponse = response as! NSHTTPURLResponse
			guard error == nil else { p.failure(.FileNotFound); return }
			switch (hresponse.statusCode) {
				case 304: //use existing
					p.success(cacheUrl)
				case 200: //dloaded it
					self.fileManager.moveTempFile(dloadUrl!, toUrl: cacheUrl, file:file, promise: &p)
				default:
					break
			}
		}
		task.resume()
		return p.future
	}
	
	///parameter destination: the directory to save the image in, overwriting any existing file
	public func downloadImage(wspace:Workspace, imageId:Int, destination:NSURL) -> Future<NSURL?,FileError>  {
		var p = Promise<NSURL?, FileError>()
		let req = request("workspaces/\(wspace.wspaceId)/images/\(imageId)", method:"GET", jsonDict:[:])
		req.addValue("image/png", forHTTPHeaderField: "Accept")
		let task = urlSession.downloadTaskWithRequest(req) { (dloadUrl, response, error) -> Void in
			let hresponse = response as? NSHTTPURLResponse
			if error == nil && hresponse?.statusCode == 200 {
				let fileUrl = NSURL(fileURLWithPath: "\(imageId).png", isDirectory: false, relativeToURL: destination)
				self.fileManager.moveTempFile(dloadUrl!, toUrl: fileUrl, file:nil, promise: &p)
			} else {
				p.failure(FileError.FailedToSaveFile)
			}
		}
		task.resume()
		return p.future
	}
}

public class LoginHandler: NSObject, NSURLSessionDataDelegate {
	let urlConfig:NSURLSessionConfiguration
	let baseUrl:NSURL
	var loggedInHandler:LoginHandler?
	var urlSession:NSURLSession!
	var loginResponse:NSURLResponse?
	var responseData:NSMutableData = NSMutableData()

	public typealias LoginHandler = (data:NSData?, response:NSHTTPURLResponse?, error:NSError?) -> Void
	
	init(config:NSURLSessionConfiguration, baseUrl:NSURL) {
		self.urlConfig = config
		self.baseUrl = baseUrl
		super.init()
	}

	public func login(login:String, password:String, handler:LoginHandler) {
		self.urlSession = NSURLSession(configuration: urlConfig, delegate: self, delegateQueue:NSOperationQueue.mainQueue())
		loggedInHandler = handler
		let url = NSURL(string: "login", relativeToURL: baseUrl)

		let req = NSMutableURLRequest(URL: url!)
		req.HTTPMethod = "POST"
		req.addValue("application/json", forHTTPHeaderField:"Content-Type")
		req.addValue("application/json", forHTTPHeaderField: "Accept")
		req.HTTPBody = try! NSJSONSerialization.dataWithJSONObject(["login":login, "password":password], options: [])

		let task = urlSession.dataTaskWithRequest(req);
		task.resume()
	}

	public func URLSession(session: NSURLSession, dataTask: NSURLSessionDataTask, didReceiveResponse response: NSURLResponse, completionHandler: (NSURLSessionResponseDisposition) -> Void)
	{
		self.loginResponse = response
		completionHandler(NSURLSessionResponseDisposition.Allow)
	}
	
	public func URLSession(session: NSURLSession, dataTask: NSURLSessionDataTask, didReceiveData data: NSData)
	{
		responseData.appendData(data)
	}
	
	public func URLSession(session: NSURLSession, task: NSURLSessionTask, didCompleteWithError error: NSError?)
	{
		if error != nil {
			loggedInHandler!(data: nil, response:loginResponse as! NSHTTPURLResponse!, error: error)
		} else {
			loggedInHandler!(data:responseData, response:loginResponse as! NSHTTPURLResponse!, error:nil)
		}
		urlSession.invalidateAndCancel()
	}
}

extension NSURLSession {
	func downloadWithPromise(request: NSURLRequest) -> (NSURLSessionDownloadTask, Future<(NSURL?, NSURLResponse?), NSError>) {
		let p = Promise<(NSURL?, NSURLResponse?), NSError>()
		let task = self.downloadTaskWithRequest(request, completionHandler:self.downloadCompletionHandler(promise:p))
		return (task, p.future)
	}
	
	func downloadCompletionHandler(promise p: Promise<(NSURL?, NSURLResponse?), NSError>) ->  (NSURL?, NSURLResponse?, NSError?) -> Void {
		return { (data, response, error) -> () in
			if let error = error {
				p.failure(error)
			} else {
				p.success(data, response)
			}
		}
	}
}
