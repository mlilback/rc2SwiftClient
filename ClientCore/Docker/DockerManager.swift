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

///manages communicating with the local docker engine
open class DockerManager : NSObject {
	let requiredApiVersion = 1.24
	fileprivate let socketPath = "/var/run/docker.sock"
	fileprivate(set) var hostUrl: String?
	fileprivate(set) var primaryVersion:Int = 0
	fileprivate(set) var secondaryVersion:Int = 0
	fileprivate(set) var fixVersion = 0
	fileprivate(set) var apiVersion:Double = 0
	let sessionConfig: URLSessionConfiguration
	let session: URLSession
	fileprivate(set) var isInstalled:Bool = false
	fileprivate var versionLoaded:Bool = false
	fileprivate(set) var installedImages:[DockerImage] = []
	fileprivate var initialzed = false
	
	///after creating, must call either initializeConnection or isDockerRunning
	public init(host:String? = nil) {
		hostUrl = host
		sessionConfig = URLSessionConfiguration.default
		sessionConfig.protocolClasses = [DockerUrlProtocol.self]
		session = URLSession(configuration: sessionConfig)
		super.init()
		isInstalled = Foundation.FileManager().fileExists(atPath: socketPath)
		//check for a host specified as an environment variable - useful for testing
		if nil == host, let envHost = ProcessInfo.processInfo.environment["DockerHostUrl"] {
			hostUrl = envHost
		}
	}
	
	///connects to the docker daemon and confirms it is running and is compatible with what we require
	public func isDockerRunning(_ handler:@escaping (Bool) -> Void) {
		initializeConnection(handler: { rsp, error in
			handler(rsp)
		})
	}
	
	public func initializeConnection(handler: @escaping SimpleServerCallback) {
		self.initialzed = true
		guard !versionLoaded else { handler(apiVersion > 0, nil); return }
		let future = dockerRequest("/version")
		processVersionFuture(future, handler: handler)
	}
	
	//test document available at fester.rc2.io
	func checkForUpdates(_ baseUrl:String, requiredVersion:Int, handler:@escaping SimpleServerCallback) {
		let url = URL(string: baseUrl)?.appendingPathComponent("/imageInfo.json")
		session.dataTask(with: url!, completionHandler: { (data, response, error) in
			guard let rawData = data , error == nil else {
				handler(false, NSError.error(withCode: .networkError, description: "failed to connect to update server", underlyingError: error as NSError?))
				return
			}
			let json = JSON(rawData)
			guard let latestVersion = json["version"].int else {
				handler(false, NSError.error(withCode: .serverError, description: "update server returned invalid data"))
				return
			}
			if latestVersion > requiredVersion {
				
			}
		}) 
	}
	
	///parses the future returned from asking docker for version info
	fileprivate func processVersionFuture(_ future:Future<JSON,NSError>, handler:@escaping SimpleServerCallback) {
		future.onSuccess { json in
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
			} catch let err as NSError {
				os_log("error getting docker version %{public}@", type:.error, err)
			}
			os_log("docker is version %d.%d.%d:%d", type:.info, self.primaryVersion, self.secondaryVersion, self.fixVersion, self.apiVersion)
			handler(self.apiVersion >= self.requiredApiVersion, nil)
			}.onFailure { error in
				os_log("error getting docker version: %{public}@", type:.error, error as NSError)
				handler(false, error as NSError)
		}
	}
	
	///makes a simple GET api request and returns the parsed results
	/// - parameter command: The api command to send. Should include initial slash.
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
	
	public func loadImages() -> Future<[DockerImage],NSError> {
		let promise = Promise<[DockerImage],NSError>()
		let future = dockerRequest("/images/json")
		print("making request")
		future.onSuccess { json in
			print("request success")
			self.installedImages.removeAll()
			for aDict in json.arrayValue {
				if let anImage = DockerImage(json: aDict), anImage.labels.keys.contains("io.rc2.type")
				{
					self.installedImages.append(anImage)
				}
				promise.success(self.installedImages)
			}
			
		}.onFailure { err in
			print("request failure")
			os_log("error reading image data from docker: %{public}s", type:.error, err)
			promise.failure(err)
		}
		return promise.future
	}
	
	public func pullImages(handler: ProgressHandler? = nil) -> (Future<Bool, NSError>, Progress) {
		let url = URL(string: hostUrl!)!
		let dbsize = installedImages.filter { $0.isNamed("rc2server/dbserver") }.reduce(0) { _, img in return img.size }
		let dbpull = DockerPullOperation(baseUrl: url, imageName: "rc2server/dbserver", estimatedSize: dbsize)
		return (dbpull.startPull(progressHandler: handler), dbpull.progress!)
	}
}

