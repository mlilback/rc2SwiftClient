//
//  DockerManager.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import SwiftyJSON
import BrightFutures
import ServiceManagement
import os

public typealias SimpleServerCallback = (_ success:Bool, _ error:NSError?) -> Void

///manages communicating with the local docker engine
open class DockerManager : NSObject {
	let requiredApiVersion = 1.24
	let sessionConfig: URLSessionConfiguration
	let session: URLSession
	let baseInfoUrl: String
	fileprivate(set) var hostUrl: String?
	fileprivate(set) var primaryVersion:Int = 0
	fileprivate(set) var secondaryVersion:Int = 0
	fileprivate(set) var fixVersion = 0
	fileprivate(set) var apiVersion:Double = 0
	fileprivate(set) var isInstalled:Bool = false
	fileprivate(set) var installedImages:[DockerImage] = []
	fileprivate(set) var imageInfo: RequiredImageInfo?
	fileprivate(set) var pullProgress: PullProgress?
	fileprivate let socketPath = "/var/run/docker.sock"
	fileprivate var initialzed = false
	fileprivate var versionLoaded:Bool = false
	
	///Default initializer. After creation, initializeConnection or isDockerRunning must be called
	/// - parameter hostUrl: The base url of the docker daemon (i.e. http://localhost:2375/) to connect to. nil means use /var/run/docker.sock. Also checks for the environment variable "DockerHostUrl" if not specified
	/// - parameter baseInfoUrl: the base url where imageInfo.json can be found. Defaults to www.rc2.io.
	public init(hostUrl host:String? = nil, baseInfoUrl infoUrl:String? = nil) {
		hostUrl = host
		self.baseInfoUrl = infoUrl == nil ? "https://www.rc2.io/" : infoUrl!
		sessionConfig = URLSessionConfiguration.default
		sessionConfig.protocolClasses = [DockerUrlProtocol.self]
		sessionConfig.requestCachePolicy = .reloadIgnoringLocalCacheData
		session = URLSession(configuration: sessionConfig)
		super.init()
		isInstalled = Foundation.FileManager().fileExists(atPath: socketPath)
		//check for a host specified as an environment variable - useful for testing
		if nil == host, let envHost = ProcessInfo.processInfo.environment["DockerHostUrl"] {
			hostUrl = envHost
		}
	}
	
	///connects to the docker daemon and confirms it is running and is compatible with what is required.
	/// calls initializeCOnnection()
	/// - parameter handler: Closure called with true if able to connect to docker daemon.
	public func isDockerRunning(_ handler:@escaping (Bool) -> Void) {
		initializeConnection(handler: { rsp, error in
			handler(rsp)
		})
	}
	
	///Loads basic version information from the docker daemon. Also loads list of docker images that are installed.
	///Must be called before being using any func except isDockerRunning().
	/// - parameter handler: Closure called with true if able to connect to docker daemon.
	public func initializeConnection(handler: @escaping SimpleServerCallback) {
		self.initialzed = true
		guard !versionLoaded else { handler(apiVersion > 0, nil); return }
		let future = dockerRequest("/version")
		future.onSuccess { json in
			if let err = self.processVersionJson(json: json) {
				handler(false, err)
				return
			}
			//successfully parsed the version info. now get the image info
			self.loadImages().onSuccess { _ in
				handler(true, nil)
			}.onFailure { error in
				handler(false, error)
			}
		}.onFailure { err in
			handler(false, err)
		}
	}
	
	///parses the version string from docker rest api
	/// - parameter json: the json returned from the rest call
	/// - returns: nil on success, NSError on failure
	fileprivate func processVersionJson(json:JSON) -> NSError? {
		do {
			let regex = try NSRegularExpression(pattern: "(\\d+)\\.(\\d+)\\.(\\d+)", options: [])
			let verStr = json["Version"].stringValue
			if let match = regex.firstMatch(in: verStr, options: [], range: NSMakeRange(0, verStr.characters.count)) {
				self.primaryVersion = Int((verStr as NSString).substring(with: match.rangeAt(1)))!
				self.secondaryVersion = Int((verStr as NSString).substring(with: match.rangeAt(2)))!
				self.fixVersion = Int((verStr as NSString).substring(with: match.rangeAt(3)))!
				self.versionLoaded = true
			} else {
				os_log("failed to parser version string", type:.info)
			}
			self.apiVersion = Double(json["ApiVersion"].stringValue)!
			os_log("docker is version %d.%d.%d:%d", type:.info, self.primaryVersion, self.secondaryVersion, self.fixVersion, self.apiVersion)
			return nil
		} catch let err as NSError {
			os_log("error getting docker version %{public}@", type:.error, err)
			return err
		}
	}
	
	///Makes a GET api request and returns the parsed json results
	/// - parameter command: The api command to send. Should include initial slash.
	/// - returns: A future for the JSON or an error.
	func dockerRequest(_ command:String) -> Future<JSON,NSError> {
		precondition(command.hasPrefix("/"))
		var urlStr = "unix://\(command)"
		if nil != hostUrl {
			urlStr = "\(hostUrl!)\(command)"
		}
		let url = URL(string: urlStr)!
		let promise = Promise<JSON,NSError>()
		let task = session.dataTask(with: URLRequest(url: url)) { data, response, error in
			guard let response = response as? HTTPURLResponse else { promise.failure(error! as NSError); return }
			if response.statusCode != 200 {
				promise.failure(NSError.error(withCode: .dockerError, description:nil))
				return
			}
			let jsonStr = String(data:data!, encoding: String.Encoding.utf8)!
			let json = JSON.parse(jsonStr)
			return promise.success(json)
		}
		task.resume()
		return promise.future
	}
	
	///fetches any missing/updated images based on imageInfo
	public func pullImages(handler: PullProgressHandler? = nil) -> Future<Bool, NSError> {
		precondition(imageInfo != nil)
		precondition(imageInfo!.dbserver.size > 0)
		let promise = Promise<Bool, NSError>()
		let url = URL(string: hostUrl!)!
		let fullSize = imageInfo!.dbserver.size + imageInfo!.appserver.size
		pullProgress = PullProgress(name: "dbserver", size: fullSize)
		let dbpull = DockerPullOperation(baseUrl: url, imageName: "rc2server/dbserver", estimatedSize: imageInfo!.dbserver.size)
		let dbfuture = pullSingleImage(pull: dbpull, progressHandler: handler)
		dbfuture.onSuccess { _ in
			let apppull = DockerPullOperation(baseUrl: url, imageName: "rc2server/appserver", estimatedSize: self.imageInfo!.appserver.size)
			let appfuture = self.pullSingleImage(pull: apppull, progressHandler: handler)
			appfuture.onSuccess { _ in
				promise.success(true)
			}.onFailure { err in
				promise.failure(err)
			}
		}.onFailure { err in
			promise.failure(err)
		}
		return promise.future
	}
	
	func pullSingleImage(pull:DockerPullOperation, progressHandler:PullProgressHandler?) -> Future<Bool, NSError>
	{
		pullProgress?.extracting = false
		let alreadyDownloaded = pullProgress!.currentSize
		let future = pull.startPull { pp in
			self.pullProgress?.currentSize = pp.currentSize + alreadyDownloaded
			self.pullProgress?.extracting = pp.extracting
			progressHandler?(self.pullProgress!)
		}
		return future
	}
	
	///make a request and return the returned data
	/// - parameter url: The URL to fetch
	/// - returns: a future for the data at url or an error
	func makeRequest(url:URL) -> Future<Data,NSError> {
		let promise = Promise<Data,NSError>()
		session.dataTask(with: url, completionHandler: { (data, response, error) in
			guard let rawData = data , error == nil else {
				promise.failure(error as! NSError)
				return
			}
			promise.success(rawData)
		}).resume()
		return promise.future
	}

	///fetches the imageInfo.json file from the internet and parses it
	func loadRequiredImageInfo() -> Future<Bool,NSError> {
		precondition(initialzed)
		let promise = Promise<Bool,NSError>()
		let updateFuture = makeRequest(url: URL(string:"\(baseInfoUrl)imageInfo.json")!)
		updateFuture.onSuccess { (data) in
			NSLog(String(data: data, encoding: .utf8)!)
			let json = JSON(data: data)
			self.imageInfo = RequiredImageInfo(json: json)
			promise.success(true)
		}.onFailure { (err) in
			promise.failure(err)
		}
		return promise.future
	}

	///requests the list of images from docker and sticks them in installedImages property
	func loadImages() -> Future<[DockerImage],NSError> {
		precondition(initialzed)
		let promise = Promise<[DockerImage],NSError>()
		loadRequiredImageInfo().onSuccess { _ in
			let future = self.dockerRequest("/images/json")
			future.onSuccess { json in
				self.installedImages.removeAll()
				for aDict in json.arrayValue {
					if let anImage = DockerImage(json: aDict), anImage.labels.keys.contains("io.rc2.type")
					{
						self.installedImages.append(anImage)
					}
				}
				promise.success(self.installedImages)
				
			}.onFailure { err in
				os_log("error reading image data from docker: %{public}s", type:.error, err)
				promise.failure(err)
			}
		}.onFailure { err in
			promise.failure(err)
		}
		return promise.future
	}
}

