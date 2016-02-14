//
//  RestServer.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import SwiftWebSocket
import BrightFutures
import Result

@objc public class RestServer : NSObject {

	private static var _sInstance:RestServer?? = nil
	private static var sInstance:RestServer? { get { return _sInstance! } set { _sInstance = newValue } }
	private let kServerHostKey = "ServerHostKey"
	
	static func createServer(appStatus appStatus:AppStatus) {
		sInstance = RestServer()
		sInstance!.appStatus = appStatus
	}
	
	///singleton accessor
	static var sharedInstance : RestServer {
		get {
			assert(sInstance != nil)
			return sInstance!
		}
	}
	
	//for dependency injection
	var fileManager:FileManager = NSFileManager.defaultManager()
	
	public typealias Rc2RestCompletionHandler = (success:Bool, results:Any?, error:NSError?) -> Void
	
	private(set) var urlConfig : NSURLSessionConfiguration
	private var urlSession : NSURLSession
	private(set) public var hosts : [NSDictionary]
	private(set) public var selectedHost : NSDictionary
	private(set) public var loginSession : LoginSession?
	private(set) var baseUrl : NSURL?
	private var userAgent: String
	private var appStatus:AppStatus?

	var restHosts : [String] {
		get {
			return hosts.map({ $0["name"]! as! String })
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
	
	//private init so instance is unique
	override init() {
		userAgent = "Rc2 iOSClient"
		#if os(OSX)
			userAgent = "Rc2 MacClient"
		#endif
		urlConfig = NSURLSessionConfiguration.defaultSessionConfiguration()
		urlConfig.HTTPAdditionalHeaders = ["User-Agent": userAgent, "Accept": "application/json"]
		urlSession = NSURLSession.init(configuration: urlConfig)
		
		//load hosts info from resource file
		let hostFileUrl = NSBundle.mainBundle().URLForResource("RestHosts", withExtension: "json")
		assert(hostFileUrl != nil, "failed to get RestHosts.json URL")
		let jsonData = NSData(contentsOfURL: hostFileUrl!)
		let json = JSON(data:jsonData!)
		let theHosts = json["hosts"].arrayObject!
		assert(theHosts.count > 0, "invalid hosts data")
		hosts = theHosts as! [NSDictionary]
		selectedHost = hosts.first!
		super.init()
		if let previousHostName = NSUserDefaults.standardUserDefaults().stringForKey(self.kServerHostKey) {
			selectHost(previousHostName)
		}
		NSNotificationCenter.defaultCenter().addObserverForName(SelectedWorkspaceChangedNotification, object: nil, queue: nil) { (note) -> Void in
			let wspace = note.object as! Box<Workspace>
			self.createSession(wspace.unbox, appStatus: self.appStatus!)
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
		if let hostDict = hosts.filter({ return ($0["name"] as! String) == hostName }).first {
			selectedHost = hostDict
			let hprotocol = hostDict["secure"]!.boolValue! ? "https" : "http"
			let hoststr = "\(hprotocol)://\(hostDict["host"]!):\(hostDict["port"]!.stringValue)/"
			baseUrl = NSURL(string: hoststr)!
		}
	}
	
	func createSession(wspace:Workspace, appStatus:AppStatus) -> Session {
		let request = NSMutableURLRequest(URL: createWebsocketUrl(wspace.wspaceId))
		request.addValue(loginSession!.authToken, forHTTPHeaderField: "Rc2-Auth")
		request.addValue(userAgent, forHTTPHeaderField: "User-Agent")
		let ws = WebSocket()
		let session = Session(wspace, source:ws, appStatus:appStatus)
		session.open(request)
		return session
	}
	
	func createWebsocketUrl(wspaceId:Int32) -> NSURL {
		let build = NSBundle(forClass: RestServer.self).infoDictionary!["CFBundleVersion"]!
		#if os(OSX)
			let client = "osx"
		#else
			let client = "ios"
		#endif
		let prot = selectedHost["secure"]!.boolValue! ? "wss" : "ws"
		let urlStr = "\(prot)://\(selectedHost["host"]!):\(selectedHost["port"]!.stringValue)/ws/\(wspaceId)?client=\(client)&build=\(build)"
		return NSURL(string: urlStr)!
	}
	
	public func login(login:String, password:String, handler:Rc2RestCompletionHandler) {
		assert(baseUrl != nil, "baseUrl not specified")
		let req = request("login", method:"POST", jsonDict: ["login":login, "password":password])
		let task = urlSession.dataTaskWithRequest(req) {
			(data, response, error) -> Void in
			guard error == nil else {
				let error = self.createError(404, description: (error?.localizedDescription)!)
				dispatch_async(dispatch_get_main_queue(), { handler(success: false, results: nil, error: error) })
				return
			}
			let json = JSON(data:data!)
			let httpResponse = response as! NSHTTPURLResponse
			switch(httpResponse.statusCode) {
				case 200:
					self.loginSession = LoginSession(json: json, host: self.selectedHost["name"]! as! String)
					//for anyone that copies our session config later, include the auth token
					self.urlConfig.HTTPAdditionalHeaders!["Rc-Auth"] = self.loginSession!.authToken
					dispatch_async(dispatch_get_main_queue(), { handler(success: true, results: self.loginSession!, error: nil) })
					NSUserDefaults.standardUserDefaults().setObject(self.loginSession!.host, forKey: self.kServerHostKey)
					NSNotificationCenter.defaultCenter().postNotificationName(RestLoginChangedNotification, object: self)
				case 401:
					let error = self.createError(401, description: "Invalid login or password")
					log.verbose("got a \(httpResponse.statusCode)")
					dispatch_async(dispatch_get_main_queue(), { handler(success: false, results: nil, error: error) })
				default:
					let error = self.createError(httpResponse.statusCode, description: "")
					log.warning("got unknown status code: \(httpResponse.statusCode)")
					dispatch_async(dispatch_get_main_queue(), { handler(success: false, results: nil, error: error) })
			}
		}
		task.resume()
	}
	
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
	}
	
	///parameter destination: the directory to save the image in, overwriting any existing file
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
				let error = self.createError(FileError.FailedToSaveFile.rawValue, description: err.localizedDescription)
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
