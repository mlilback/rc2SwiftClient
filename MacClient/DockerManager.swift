//
//  DockerManager.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import SwiftyJSON
import BrightFutures

///manages communicating with the local docker engine
public class DockerManager {
	private let socketPath:String
	private(set) var primaryVersion:Int = 0
	private(set) var secondaryVersion:Int = 0
	private(set) var fixVersion = 0
	private(set) var apiVersion:Double = 0
	let sessionConfig: NSURLSessionConfiguration
	let session: NSURLSession
	let isInstalled:Bool
	private var versionLoaded:Bool = false
	
	init(path:String = "/var/run/docker.sock") {
		socketPath = path
		sessionConfig = NSURLSessionConfiguration.defaultSessionConfiguration()
		sessionConfig.protocolClasses = [DockerUrlProtocol.self]
		session = NSURLSession(configuration: sessionConfig)

		isInstalled = NSFileManager().fileExistsAtPath(socketPath)
		if isInstalled {
			fetchVersion()
		}
	}
	
	/// returns a future for knowing if we can use this user's docker installation
	func hasAcceptableDockerInstallation() -> Future<Bool,NSError> {
		let promise = Promise<Bool,NSError>()
		let future = dockerRequest("/version")
		future.onSuccess { json in
			promise.success(self.apiVersion >= 1.24)
		}.onFailure { error in
			promise.failure(error)
		}
		return promise.future
	}
	
	///asynchronously fetch version information
	func fetchVersion() {
		let future = dockerRequest("/version")
		processVersionFuture(future)
	}
	
	///parses the future returned from asking docker for version info
	func processVersionFuture(future:Future<JSON,NSError>) {
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
		}.onFailure { error in
			log.warning("error getting docker version: \(error)")
		}
	}
	
	///makes a simple GET api request and returns the parsed results
	/// - parameter command: The api command to send. Should include initial slash.
	func dockerRequest(command:String) -> Future<JSON,NSError> {
		precondition(command.hasPrefix("/"))
		let url = NSURL(string: "unix://\(command)")!
		let promise = Promise<JSON,NSError>()
		let task = session.dataTaskWithRequest(NSURLRequest(URL: url)) { data, response, error in
			guard let response = response as? NSHTTPURLResponse else { promise.failure(error!); return }
			if response.statusCode != 200 {
				promise.failure(NSError.error(withCode: .DockerError, description:nil))
				return
			}
			let json = JSON.parse(String(data:data!, encoding: NSUTF8StringEncoding)!)
			guard json.dictionary != nil else { return promise.failure(NSError.error(withCode: .DockerError, description:"")) }
			return promise.success(json)
		}
		task.resume()
		return promise.future
	}
}
