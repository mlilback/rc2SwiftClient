//
//  DockerManager.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import SwiftyJSON
import BrightFutures
import ServiceManagement
import ClientCore

///manages communicating with the local docker engine
public class DockerManager : NSObject {
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
	
	override init() {
		sessionConfig = NSURLSessionConfiguration.defaultSessionConfiguration()
		sessionConfig.protocolClasses = [DockerUrlProtocol.self]
		session = NSURLSession(configuration: sessionConfig)
		super.init()
		isInstalled = NSFileManager().fileExistsAtPath(socketPath)
	}
	
	///connects to the docker daemon and confirms it is running and is compatible with what we require
	func isDockerRunning(handler:(Bool) -> Void) {
		initializeConnection("http://10.0.1.9:2375/", handler: { rsp, error in handler(rsp) })
	}
	
	func initializeConnection(url:String?, handler: SimpleServerCallback) {
		if nil == hostUrl { hostUrl = url }
		guard !versionLoaded else { handler(success: apiVersion > 0, error: nil); return }
		let future = dockerRequest("/version")
		processVersionFuture(future, handler: handler)
	}
	
	//test document available at fester.rc2.io
	func checkForUpdates(baseUrl:String, requiredVersion:Int, handler:SimpleServerCallback) {
		let url = NSURL(string: baseUrl)?.URLByAppendingPathComponent("/localServer.json")
		session.dataTaskWithURL(url!) { (data, response, error) in
			guard let rawData = data where error == nil else {
				handler(success: false, error: NSError.error(withCode: .NetworkError, description: "failed to connect to update server", underlyingError: error))
				return
			}
			let json = JSON(rawData)
			guard let latestVersion = json["latestVersion"].int else {
				handler(success: false, error: NSError.error(withCode: .ServerError, description: "update server returned invalid data"))
				return
			}
			if latestVersion > requiredVersion {
				
			}
		}
	}
	
	///parses the future returned from asking docker for version info
	private func processVersionFuture(future:Future<JSON,NSError>, handler:SimpleServerCallback) {
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
			handler(success: self.apiVersion >= self.requiredApiVersion, error: nil)
			}.onFailure { error in
				log.warning("error getting docker version: \(error)")
				handler(success: false, error: error as NSError)
		}
	}
	
	///makes a simple GET api request and returns the parsed results
	/// - parameter command: The api command to send. Should include initial slash.
	private func dockerRequest(command:String) -> Future<JSON,NSError> {
		precondition(command.hasPrefix("/"))
		var urlStr = "unix://\(command)"
		if nil != hostUrl {
			urlStr = "\(hostUrl!)\(command)"
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
	
	func pullImage(imageName:String) -> Future<Bool, NSError> {
		let pullTask = DockerPullOperation(baseUrl: NSURL(string: hostUrl!)!, imageName: imageName)
		pullTask.start()
		return pullTask.promise.future
	}
	
//	private let socketPath:String
//	private(set) var primaryVersion:Int = 0
//	private(set) var secondaryVersion:Int = 0
//	private(set) var fixVersion = 0
//	private(set) var apiVersion:Double = 0
//	let sessionConfig: NSURLSessionConfiguration
//	let session: NSURLSession
//	private(set) var isInstalled:Bool = false
//	private var versionLoaded:Bool = false
//	
//	init(path:String = "/var/run/docker.sock") {
//		socketPath = path
//		sessionConfig = NSURLSessionConfiguration.defaultSessionConfiguration()
//		sessionConfig.protocolClasses = [DockerUrlProtocol.self]
//		session = NSURLSession(configuration: sessionConfig)
//		super.init()
//		isInstalled = NSFileManager().fileExistsAtPath(socketPath)
//		if isInstalled {
//			fetchVersion()
//		}
//	}
//	
//	/// returns a future for knowing if we can use this user's docker installation
//	func hasAcceptableDockerInstallation() -> Future<Bool,NSError> {
//		let promise = Promise<Bool,NSError>()
//		let future = dockerRequest("/version")
//		future.onSuccess { json in
//			promise.success(self.apiVersion >= 1.24)
//		}.onFailure { error in
//			promise.failure(error)
//		}
//		return promise.future
//	}
//	
//	///asynchronously fetch version information
//	func fetchVersion() {
//		let future = dockerRequest("/version")
//		processVersionFuture(future)
//	}
//	
//	///parses the future returned from asking docker for version info
//	func processVersionFuture(future:Future<JSON,NSError>) {
//		future.onSuccess { json in
//			do {
//				let regex = try NSRegularExpression(pattern: "(\\d+)\\.(\\d+)\\.(\\d+)", options: [])
//				let verStr = json["Version"].stringValue
//				if let match = regex.firstMatchInString(verStr, options: [], range: NSMakeRange(0, verStr.characters.count)) {
//					self.primaryVersion = Int((verStr as NSString).substringWithRange(match.rangeAtIndex(1)))!
//					self.secondaryVersion = Int((verStr as NSString).substringWithRange(match.rangeAtIndex(2)))!
//					self.fixVersion = Int((verStr as NSString).substringWithRange(match.rangeAtIndex(3)))!
//					self.versionLoaded = true
//				} else {
//					log.info("failed to parser version string")
//				}
//				self.apiVersion = Double(json["ApiVersion"].stringValue)!
//			} catch let err as NSError {
//				log.error("error getting docker version \(err)")
//			}
//		}.onFailure { error in
//			log.warning("error getting docker version: \(error)")
//		}
//	}
//	
//	///makes a simple GET api request and returns the parsed results
//	/// - parameter command: The api command to send. Should include initial slash.
//	func dockerRequest(command:String) -> Future<JSON,NSError> {
//		precondition(command.hasPrefix("/"))
//		let url = NSURL(string: "unix://\(command)")!
//		let promise = Promise<JSON,NSError>()
//		let task = session.dataTaskWithRequest(NSURLRequest(URL: url)) { data, response, error in
//			guard let response = response as? NSHTTPURLResponse else { promise.failure(error!); return }
//			if response.statusCode != 200 {
//				promise.failure(NSError.error(withCode: .DockerError, description:nil))
//				return
//			}
//			let json = JSON.parse(String(data:data!, encoding: NSUTF8StringEncoding)!)
//			guard json.dictionary != nil else { return promise.failure(NSError.error(withCode: .DockerError, description:"")) }
//			return promise.success(json)
//		}
//		task.resume()
//		return promise.future
//	}
//	
//	///prompt user to install server
//	func promptToInstallServer() {
//		let defaults = NSUserDefaults.standardUserDefaults()
//		guard defaults.boolForKey(DockerPrefKey.DidInstallPrompt) == false else { return }
//		defer { defaults.setBool(true, forKey: DockerPrefKey.DidInstallPrompt) }
//		
//		let alert = NSAlert()
//		alert.messageText = localizedString(.InitialPromptMessage)
//		alert.informativeText = localizedString(.InitialPromptInfo)
//		alert.addButtonWithTitle(localizedString(.InitalPromptOk))
//		alert.addButtonWithTitle(NSLocalizedString("Cancel", comment: ""))
//		let response = alert.runModal()
//		guard response == NSAlertFirstButtonReturn else { return }
//		beginInstallProcess(nil)
//	}
//	
//	///begins local server install process
//	@IBAction func beginInstallProcess(sender:AnyObject?) {
//		
//	}
//	
//	@IBAction func resetServerInstall(sender:AnyObject?) {
//		
//	}
//	
//	private func localizedString(key : DockerString) -> String {
//		return NSLocalizedString("LocalServer.\(key.rawValue)", comment: "")
//	}
//	
//	struct DockerPrefKey {
//		static let DidInstallPrompt = "LocalServer.DidInitialPrompt"
//	}
//	
//	private enum DockerString: String {
//		case InitialPromptMessage
//		case InitialPromptInfo
//		case InitalPromptOk
//	}
}

