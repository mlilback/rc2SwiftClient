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
import os

@objc open class RestServer : NSObject, URLSessionTaskDelegate {

	fileprivate let kServerHostKey = "ServerHostKey"
	
	//for dependency injection
	var fileManager:Rc2FileManager = Rc2DefaultFileManager()
	
	public typealias Rc2RestCompletionHandler = (_ success:Bool, _ results:Any?, _ error:NSError?) -> Void
	
	fileprivate(set) var urlConfig : URLSessionConfiguration!
	fileprivate var urlSession : URLSession!
	let host:ServerHost
	fileprivate(set) open var loginSession : LoginSession?
	fileprivate(set) var baseUrl : URL?
	fileprivate var userAgent: String
	weak var appStatus:AppStatus?
	fileprivate(set) var session:Session?

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
	
	init(host:ServerHost) {
		userAgent = "Rc2 iOSClient"
		#if os(OSX)
			userAgent = "Rc2 MacClient"
		#endif
		self.host = host
		super.init()
		urlConfig = URLSessionConfiguration.default
		urlConfig.httpAdditionalHeaders = ["User-Agent": userAgent, "Accept": "application/json"]
		urlSession = URLSession(configuration: urlConfig, delegate: self, delegateQueue:OperationQueue.main)
	}

	///give a hostname from hosts property, the list of last known workspace names
	func workspaceNamesForHostName(_ hostName:String, userName:String) -> [String] {
		let defaults = UserDefaults.standard
		let key = "ws//\(hostName)//\(userName)"
		if let names = defaults.object(forKey: key) as? [String] , names.count > 0 {
			return names
		}
		return ["Default"]
	}
	
	fileprivate func createError(_ err:FileError, description:String) -> NSError {
		switch(err) {
			case .foundationError(let nserror):
				return nserror
			default:
				return NSError(domain: Rc2ErrorDomain, code: 1, userInfo: [NSLocalizedDescriptionKey:NSLocalizedString(description, comment: "")])
		}
	}
	
	fileprivate func createError(_ code:Int, description:String) -> NSError {
		return NSError(domain: Rc2ErrorDomain, code: code, userInfo: [NSLocalizedDescriptionKey:NSLocalizedString(description, comment: "")])
	}
	
	fileprivate func request(_ path:String, method:String, jsonDict:NSDictionary) -> URLRequest {
		let url = URL(string: path, relativeTo: baseUrl)
		var request = URLRequest(url: url!)
		request.httpMethod = method
		if loginSession != nil {
			request.addValue(loginSession!.authToken, forHTTPHeaderField:"Rc2-Auth")
		}
		if (jsonDict.count > 0) {
			request.addValue("application/json", forHTTPHeaderField:"Content-Type")
			request.httpBody = try! JSONSerialization.data(withJSONObject: jsonDict, options: [])
		}
		return request
	}
	
	func createSession(_ wspace:Workspace, appStatus:AppStatus) -> Future<Session, NSError> {
		var request = URLRequest(url: createWebsocketUrl(wspace.wspaceId))
		request.addValue(loginSession!.authToken, forHTTPHeaderField: "Rc2-Auth")
		request.addValue(userAgent, forHTTPHeaderField: "User-Agent")
		let ws = WebSocket()
		session = Session(wspace, source:ws, restServer:self, appStatus:appStatus, networkConfig:urlConfig, hostIdentifier: host.host)
		return session!.open(request)
	}
	
	func createWebsocketUrl(_ wspaceId:Int32) -> URL {
		let build = Bundle(for: RestServer.self).infoDictionary!["CFBundleVersion"]!
		#if os(OSX)
			let client = "osx"
		#else
			let client = "ios"
		#endif
		let prot = host.secure ? "wss" : "ws"
		let urlStr = "\(prot)://\(host.host):\(host.port)/ws/\(wspaceId)?client=\(client)&build=\(build)"
		return URL(string: urlStr)!
	}
	
	open func login(_ password:String) -> Future<LoginSession,NSError> {
		let hprotocol = host.secure ? "https" : "http"
		let hoststr = "\(hprotocol)://\(host.host):\(host.port)/"
		baseUrl = URL(string: hoststr)!
		assert(baseUrl != nil, "baseUrl not specified")
		let promise = Promise<LoginSession,NSError>()
		let loginObj = LoginHandler(config: urlConfig, baseUrl: baseUrl!)
		loginObj.login(host.user, password:password) { (data, response, error) -> Void in
			guard error == nil else {
				let appError = self.createError(404, description: (error?.localizedDescription)!)
				promise.failure(appError)
				return
			}
			let json = JSON(data:data!)
			switch(response!.statusCode) {
				case 200:
					self.loginSession = LoginSession(json: json, host: self.host.host)
					//store list of workspace names for this session
//					let wspaceListKey = "ws//\(self.selectedHost.name)//\(login)"
//					NSUserDefaults.standardUserDefaults().setObject(self.loginSession!.workspaces.map() { $0.name }, forKey: wspaceListKey)
					//for anyone that copies our session config later, include the auth token
					self.urlConfig.httpAdditionalHeaders!["Rc2-Auth"] = self.loginSession!.authToken
					promise.success(self.loginSession!)
					UserDefaults.standard.set(self.loginSession!.host, forKey: self.kServerHostKey)
				case 401:
					let error = self.createError(401, description: "Invalid login or password")
					os_log("got a %@", type:.debug, response!.statusCode)
					promise.failure(error)
				default:
					let error = self.createError(response!.statusCode, description: "")
					os_log("got unknown status code: %@", response!.statusCode)
					promise.failure(error)
			}
		}
		return promise.future
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
	open func downloadImage(_ wspace:Workspace, imageId:Int, destination:URL, handler:@escaping Rc2RestCompletionHandler) {
		let req = request("workspaces/\(wspace.wspaceId)/images/\(imageId)", method:"GET", jsonDict:[:])
		let (task, f) = urlSession.downloadWithPromise(req)
		task.resume()
		f.onSuccess(DispatchQueue.main.context) { (dloadUrl, response) in
			let fileUrl = URL(fileURLWithPath: "\(imageId).png", isDirectory: false, relativeTo: destination)
			do {
				if try fileUrl.checkResourceIsReachable() {
					try self.fileManager.removeItem(at:fileUrl)
				}
				try self.fileManager.moveItem(at: dloadUrl!, to: fileUrl)
				handler(true, fileUrl, nil)
			} catch let err as NSError {
				let error = self.createError(FileError.failedToSaveFile, description: err.localizedDescription)
				handler(false, nil, error)
			}
		}.onFailure(DispatchQueue.main.context) { (error) in
			handler(false, nil, error)
		}
	}

	open func downloadFile(_ wspace:Workspace, file:File, to destDirUrl:URL) -> Future<URL?, FileError> {
		var p = Promise<URL?,FileError>()
		let cacheUrl = URL(fileURLWithPath: file.name, relativeTo: destDirUrl)
		var req = request("workspaces/\(wspace.wspaceId)/files/\(file.fileId)", method: "GET", jsonDict: [:])
		do {
			if try cacheUrl.checkResourceIsReachable() {
				req.addValue("f/\(file.fileId)/\(file.version)", forHTTPHeaderField: "If-None-Match")
			}
		} catch {
		}
		req.addValue(file.fileType.mimeType, forHTTPHeaderField: "Accept")
		let task = urlSession.downloadTask(with: req) { (dloadUrl, response, error) -> Void in
			let hresponse = response as! HTTPURLResponse
			guard error == nil else { p.failure(.fileNotFound); return }
			switch (hresponse.statusCode) {
				case 304: //use existing
					p.success(cacheUrl)
				case 200: //dloaded it
					self.fileManager.move(tempFile:dloadUrl!, to: cacheUrl, file:file, promise: &p)
				default:
					break
			}
		}
		task.resume()
		return p.future
	}
	
	///parameter destination: the directory to save the image in, overwriting any existing file
	open func downloadImage(_ wspace:Workspace, imageId:Int, destination:URL) -> Future<URL?,FileError>  {
		var p = Promise<URL?, FileError>()
		var req = request("workspaces/\(wspace.wspaceId)/images/\(imageId)", method:"GET", jsonDict:[:])
		req.addValue("image/png", forHTTPHeaderField: "Accept")
		let task = urlSession.downloadTask(with: req) { (dloadUrl, response, error) -> Void in
			let hresponse = response as? HTTPURLResponse
			if error == nil && hresponse?.statusCode == 200 {
				let fileUrl = URL(fileURLWithPath: "\(imageId).png", isDirectory: false, relativeTo: destination)
				self.fileManager.move(tempFile: dloadUrl!, to: fileUrl, file:nil, promise: &p)
			} else {
				p.failure(FileError.failedToSaveFile)
			}
		}
		task.resume()
		return p.future
	}
}

open class LoginHandler: NSObject, URLSessionDataDelegate {
	let urlConfig:URLSessionConfiguration
	let baseUrl:URL
	var loggedInHandler:LoginHandler?
	var urlSession:Foundation.URLSession!
	var loginResponse:URLResponse?
	var responseData:NSMutableData = NSMutableData()

	public typealias LoginHandler = (_ data:Data?, _ response:HTTPURLResponse?, _ error:NSError?) -> Void
	
	init(config:URLSessionConfiguration, baseUrl:URL) {
		self.urlConfig = config
		self.baseUrl = baseUrl
		super.init()
	}

	open func login(_ login:String, password:String, handler:@escaping LoginHandler) {
		self.urlSession = Foundation.URLSession(configuration: urlConfig, delegate: self, delegateQueue:OperationQueue.main)
		loggedInHandler = handler
		let url = URL(string: "login", relativeTo: baseUrl)

		var req = URLRequest(url: url!)
		req.httpMethod = "POST"
		req.addValue("application/json", forHTTPHeaderField:"Content-Type")
		req.addValue("application/json", forHTTPHeaderField: "Accept")
		req.httpBody = try! JSONSerialization.data(withJSONObject: ["login":login, "password":password], options: [])

		let task = urlSession.dataTask(with: req);
		task.resume()
	}

	open func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void)
	{
		self.loginResponse = response
		completionHandler(Foundation.URLSession.ResponseDisposition.allow)
	}
	
	open func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data)
	{
		responseData.append(data)
	}
	
	open func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?)
	{
		if error != nil {
			loggedInHandler!(nil, loginResponse as! HTTPURLResponse!, error as NSError?)
		} else {
			loggedInHandler!(responseData as Data, loginResponse as! HTTPURLResponse!, nil)
		}
		urlSession.invalidateAndCancel()
	}
}

extension URLSession {
	func downloadWithPromise(_ request: URLRequest) -> (URLSessionDownloadTask, Future<(URL?, URLResponse?), NSError>) {
		let p = Promise<(URL?, URLResponse?), NSError>()
		let task = self.downloadTask(with:request, completionHandler:self.downloadCompletionHandler(promise:p))
		return (task, p.future)
	}
	
	func downloadCompletionHandler(promise p: Promise<(URL?, URLResponse?), NSError>) ->  (URL?, URLResponse?, Error?) -> Void {
		return { (data, response, error) -> () in
			if let error = error {
				p.failure(error as NSError)
			} else {
				p.success(data, response)
			}
		}
	}
}
