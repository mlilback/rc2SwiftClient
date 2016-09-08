//
//  LocalDockerServer.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import SwiftyJSON
import BrightFutures
import LocalServerCore
import ClientCore

@objc class LocalDockerServer: NSObject, LocalServerProtocol, NSXPCListenerDelegate {
	let requiredApiVersion = 1.24
	private let socketPath = "/var/run/docker.sock"
	private(set) var hostUrl: String?
	private(set) var primaryVersion:Int = 0
	private(set) var secondaryVersion:Int = 0
	private(set) var fixVersion = 0
	private(set) var apiVersion:Double = 0
	let sessionConfig: NSURLSessionConfiguration
	let session: NSURLSession
	private(set) var isInstalled:Bool = false
	private var versionLoaded:Bool = false
	private weak var currentConnection: NSXPCConnection?
	
	override init() {
		sessionConfig = NSURLSessionConfiguration.defaultSessionConfiguration()
		sessionConfig.protocolClasses = [DockerUrlProtocol.self]
		session = NSURLSession(configuration: sessionConfig)
		super.init()
		isInstalled = NSFileManager().fileExistsAtPath(socketPath)
		log.info("server initialized")
	}
	
	///parses the future returned from asking docker for version info
	func processVersionFuture(future:Future<JSON,NSError>, handler:SimpleServerCallback) {
		future.onSuccess { json in
			do {
				let regex = try NSRegularExpression(pattern: "(\\d+)\\.(\\d+)\\.(\\d+)", options: [])
				let verStr = json["Version"].stringValue
				if let match = regex.firstMatchInString(verStr, options: [], range: NSMakeRange(0, verStr.characters.count)) {
					self.primaryVersion = Int((verStr as NSString).substringWithRange(match.rangeAtIndex(1)))!
					self.secondaryVersion = Int((verStr as NSString).substringWithRange(match.rangeAtIndex(2)))!
					self.fixVersion = Int((verStr as NSString).substringWithRange(match.rangeAtIndex(3)))!
					self.versionLoaded = true
				} else {
					log.info("failed to parser version string")
				}
				self.apiVersion = Double(json["ApiVersion"].stringValue)!
			} catch let err as NSError {
				log.error("error getting docker version \(err)")
			}
			log.info("docker is version \(self.primaryVersion).\(self.secondaryVersion).\(self.fixVersion):\(self.apiVersion)")
			handler(self.apiVersion >= self.requiredApiVersion, nil)
		}.onFailure { error in
			log.warning("error getting docker version: \(error)")
			handler(false, error as NSError)
		}
	}

	///makes a simple GET api request and returns the parsed results
	/// - parameter command: The api command to send. Should include initial slash.
	func dockerRequest(command:String) -> Future<JSON,NSError> {
		precondition(command.hasPrefix("/"))
		var urlStr = "unix://\(command)"
		if nil != hostUrl {
			urlStr = "\(hostUrl)\(command)"
		}
		let url = NSURL(string: urlStr)!
		let promise = Promise<JSON,NSError>()
		let task = session.dataTaskWithRequest(NSURLRequest(URL: url)) { data, response, error in
			guard let response = response as? NSHTTPURLResponse else { promise.failure(error!); return }
			if response.statusCode != 200 {
				promise.failure(NSError.error(withCode: .DockerError, description:nil))
				return
			}
			let jsonStr = String(data:data!, encoding: NSUTF8StringEncoding)!
			let json = JSON.parse(jsonStr)
			guard json.dictionary != nil else { return promise.failure(NSError.error(withCode: .DockerError, description:"")) }
			return promise.success(json)
		}
		task.resume()
		return promise.future
	}

	func listener(listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
		//only allow 1 connection
		guard nil == currentConnection else { log.error("request for second connection"); return false }
		newConnection.exportedInterface = NSXPCInterface(withProtocol: LocalServerProtocol.self)
		newConnection.exportedObject = self
		currentConnection = newConnection
		newConnection.resume()
		return true
	}
	
	func initializeConnection(url:String?, handler: SimpleServerCallback) {
		if nil == hostUrl { hostUrl = url }
		guard !versionLoaded else { handler(apiVersion > 0, nil); return }
		let future = dockerRequest("/version")
		processVersionFuture(future, handler: handler)
	}
	
	//test document available at fester.rc2.io
	func checkForUpdates(baseUrl:String, requiredVersion:Int, handler:SimpleServerCallback) {
		let url = NSURL(string: baseUrl)?.URLByAppendingPathComponent("/localServer.json")
		session.dataTaskWithURL(url!) { (data, response, error) in
			guard let rawData = data where error == nil else {
				handler(false, NSError.error(withCode: .NetworkError, description: "failed to connect to update server", underlyingError: error))
				return
			}
			let json = JSON(rawData)
			guard let latestVersion = json["latestVersion"].int else {
				handler(false, NSError.error(withCode: .ServerError, description: "update server returned invalid data"))
				return
			}
			if latestVersion > requiredVersion {
				
			}
		}
	}
	
	func runLoopNotification(activity:CFRunLoopActivity) {
		if activity == .Entry {
			log.info("run loop starting")
		} else if activity == .Exit {
			log.info("run loop exiting")
		}
	}
}
