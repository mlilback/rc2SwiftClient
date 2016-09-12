//
//  DockerManager.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import SwiftyJSON
import BrightFutures
import os

///manages communicating with the local docker engine
open class DockerManager : NSObject {
	fileprivate let socketPath:String
	fileprivate(set) var primaryVersion:Int = 0
	fileprivate(set) var secondaryVersion:Int = 0
	fileprivate(set) var fixVersion = 0
	fileprivate(set) var apiVersion:Double = 0
	let sessionConfig: URLSessionConfiguration
	let session: URLSession
	fileprivate(set) var isInstalled:Bool = false
	fileprivate var versionLoaded:Bool = false
	
	init(path:String = "/var/run/docker.sock") {
		socketPath = path
		sessionConfig = URLSessionConfiguration.default
		sessionConfig.protocolClasses = [DockerUrlProtocol.self]
		session = URLSession(configuration: sessionConfig)
		super.init()
		isInstalled = Foundation.FileManager().fileExists(atPath: socketPath)
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
	func processVersionFuture(_ future:Future<JSON,NSError>) {
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
				os_log("error getting docker version %@", err)
			}
		}.onFailure { error in
			os_log("error getting docker version: %@", error)
		}
	}
	
	///makes a simple GET api request and returns the parsed results
	/// - parameter command: The api command to send. Should include initial slash.
	func dockerRequest(_ command:String) -> Future<JSON,NSError> {
		precondition(command.hasPrefix("/"))
		let url = URL(string: "unix://\(command)")!
		let promise = Promise<JSON,NSError>()
		let task = session.dataTask(with: URLRequest(url: url)) { data, response, error in
			guard let response = response as? HTTPURLResponse else { promise.failure(error! as NSError); return }
			if response.statusCode != 200 {
				promise.failure(NSError.error(withCode: .dockerError, description:nil))
				return
			}
			let json = JSON.parse(String(data:data!, encoding: String.Encoding.utf8)!)
			guard json.dictionary != nil else { return promise.failure(NSError.error(withCode: .dockerError, description:"")) }
			return promise.success(json)
		}
		task.resume()
		return promise.future
	}
	
	///prompt user to install server
	func promptToInstallServer() {
		let defaults = UserDefaults.standard
		guard defaults.bool(forKey: DockerPrefKey.DidInstallPrompt) == false else { return }
		defer { defaults.set(true, forKey: DockerPrefKey.DidInstallPrompt) }
		
		let alert = NSAlert()
		alert.messageText = localizedString(.InitialPromptMessage)
		alert.informativeText = localizedString(.InitialPromptInfo)
		alert.addButton(withTitle: localizedString(.InitalPromptOk))
		alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
		let response = alert.runModal()
		guard response == NSAlertFirstButtonReturn else { return }
		beginInstallProcess(nil)
	}
	
	///begins local server install process
	@IBAction func beginInstallProcess(_ sender:AnyObject?) {
		
	}
	
	@IBAction func resetServerInstall(_ sender:AnyObject?) {
		
	}
	
	fileprivate func localizedString(_ key : DockerString) -> String {
		return NSLocalizedString("LocalServer.\(key.rawValue)", comment: "")
	}
	
	struct DockerPrefKey {
		static let DidInstallPrompt = "LocalServer.DidInitialPrompt"
	}
	
	fileprivate enum DockerString: String {
		case InitialPromptMessage
		case InitialPromptInfo
		case InitalPromptOk
	}
}

