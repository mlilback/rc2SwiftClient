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
import SwiftyUserDefaults

///a callback closure
public typealias SimpleServerCallback = (_ success:Bool, _ error:NSError?) -> Void

extension DefaultsKeys {
	//MARK: - Keys for UserDefaults
	static let lastImageInfoCheck = DefaultsKey<Double>("lastImageInfoCheck")
	static let dockerImageVersion = DefaultsKey<Int>("dockerImageVersion")
	static let cachedImageInfo = DefaultsKey<JSON?>("cachedImageInfo")
}

//MARK: -
///manages communicating with the local docker engine
open class DockerManager : NSObject {
	//MARK: - Properties
	let networkName = "rc2server"
	let requiredApiVersion = 1.24
	let sessionConfig: URLSessionConfiguration
	let session: URLSession
	let baseInfoUrl: String
	let defaults: UserDefaults
	///the base url to connect to. will be set in init, but unwrapped since might be after call to super.init
	fileprivate(set) var baseUrl: URL!
	fileprivate(set) var primaryVersion:Int = 0
	fileprivate(set) var secondaryVersion:Int = 0
	fileprivate(set) var fixVersion = 0
	fileprivate(set) var apiVersion:Double = 0
	fileprivate(set) var isInstalled:Bool = false
	fileprivate(set) var installedImages:[DockerImage] = []
	fileprivate(set) var imageInfo: RequiredImageInfo?
	fileprivate(set) var pullProgress: PullProgress?
	fileprivate(set) var dataDirectory:URL?
	fileprivate let socketPath = "/var/run/docker.sock"
	fileprivate var initialzed = false
	fileprivate var versionLoaded:Bool = false
	
	///has enough time elapsed that we should check to see if there is an update to the docker images
	public var shouldCheckForUpdate: Bool {
		return defaults[.lastImageInfoCheck] + 86400.0 <= Date.timeIntervalSinceReferenceDate
	}
	
	//MARK: - Public Methods
	
	///Default initializer. After creation, initializeConnection or isDockerRunning must be called
	/// - parameter hostUrl: The base url of the docker daemon (i.e. http://localhost:2375/) to connect to. nil means use /var/run/docker.sock. Also checks for the environment variable "DockerHostUrl" if not specified
	/// - parameter baseInfoUrl: the base url where imageInfo.json can be found. Defaults to www.rc2.io.
	/// - parameter userDefaults: defaults to standard user defaults. Allows for dependency injection.
	public init(hostUrl host:String? = nil, baseInfoUrl infoUrl:String? = nil, userDefaults:UserDefaults = .standard, sessionConfiguration:URLSessionConfiguration = .default)
	{
		if let hostUrl = host {
			baseUrl = URL(string: hostUrl)!
		} else {
			baseUrl = URL(string: "unix://")
		}
		self.baseInfoUrl = infoUrl == nil ? "https://www.rc2.io/" : infoUrl!
		defaults = userDefaults
		sessionConfig = sessionConfiguration
		sessionConfig.protocolClasses = [DockerUrlProtocol.self] as [AnyClass] + sessionConfig.protocolClasses!
		sessionConfig.requestCachePolicy = .reloadIgnoringLocalCacheData
		session = URLSession(configuration: sessionConfig)
		//read image info if it is there
		imageInfo = RequiredImageInfo(json: defaults[.cachedImageInfo])
		super.init()
		isInstalled = Foundation.FileManager().fileExists(atPath: socketPath)
		//check for a host specified as an environment variable - useful for testing
		if nil == host, let envHost = ProcessInfo.processInfo.environment["DockerHostUrl"] {
			baseUrl = URL(string:envHost)
		}
		assert(baseUrl != nil, "hostUrl not specified as argument or environment variable")
	}
	
	///connects to the docker daemon and confirms it is running and meets requirements.
	/// calls initializeConnection()
	/// - returns: Closure called with true if able to connect to docker daemon.
	public func isDockerRunning() -> Future<Bool, NSError> {
		guard initialzed else { return initializeConnection() }
		let promise = Promise<Bool,NSError>()
		promise.success(true)
		return promise.future
	}
	
	///Loads basic version information from the docker daemon. Also loads list of docker images that are installed.
	///Must be called before being using any func except isDockerRunning().
	/// - returns: future. the result will be false if there was an error parsing information from docker.
	public func initializeConnection() -> Future<Bool, NSError> {
		self.initialzed = true
		let promise = Promise<Bool, NSError>()
		guard !versionLoaded else { promise.success(apiVersion > 0); return promise.future }
		let future = dockerRequest("/version")
		future.onSuccess { json in
			if let err = self.processVersionJson(json: json) {
				promise.failure(err)
			} else {
				//successfully parsed the version info. now get the image info
				self.loadImages().onSuccess { _ in
					promise.success(true)
				}.onFailure { error in
					promise.failure(error)
				}
			}
		}.onFailure { err in
			promise.failure(err)
		}
		return promise.future
	}
	
	///Checks to see if it is necessary to check for an imageInfo update, and if so, perform that check.
	/// - returns: a future whose success will be true if a pull is required
	public func checkForImageUpdate() -> Future<Bool,NSError> {
		precondition(initialzed)
		let promise = Promise<Bool,NSError>()
		//short circuit if we don't need to chedk and have valid data
		guard imageInfo == nil || shouldCheckForUpdate else {
			os_log("using cached docker info", type:.info)
			promise.success(false)
			return promise.future
		}
		let updateFuture = makeRequest(url: URL(string:"\(baseInfoUrl)imageInfo.json")!)
		updateFuture.onSuccess { (data) in
			let json = JSON(data: data)
			self.imageInfo = RequiredImageInfo(json: json)
			self.defaults[.cachedImageInfo] = json
			self.defaults[.lastImageInfoCheck] = Date.timeIntervalSinceReferenceDate
			promise.success(true)
		}.onFailure { (err) in
			promise.failure(err)
		}
		return promise.future
	}
	
	///compares installedImages with imageInfo to see if a pull is necessary
	public func pullIsNecessary() -> Bool {
		//TODO: we need tag/version info as part of the images
		for aTag in [imageInfo!.dbserver.tag, imageInfo!.appserver.tag, imageInfo!.computeserver.tag] {
			if installedImages.filter({ img in img.isNamed(aTag) }).count < 1 {
				return true
			}
		}
		os_log("no pull necessary", type:.info)
		return false
	}
	
	///fetches any missing/updated images based on imageInfo
	public func pullImages(handler: PullProgressHandler? = nil) -> Future<Bool, NSError> {
		precondition(imageInfo != nil)
		precondition(imageInfo!.dbserver.size > 0)
		let promise = Promise<Bool, NSError>()
		let fullSize = imageInfo!.dbserver.size + imageInfo!.appserver.size + imageInfo!.computeserver.size
		pullProgress = PullProgress(name: "dbserver", size: fullSize)
		let dbpull = DockerPullOperation(baseUrl: baseUrl, imageName: "rc2server/dbserver", estimatedSize: imageInfo!.dbserver.size)
		let dbfuture = pullSingleImage(pull: dbpull, progressHandler: handler)
		dbfuture.onSuccess { _ in
			let apppull = DockerPullOperation(baseUrl: self.baseUrl, imageName: "rc2server/appserver", estimatedSize: self.imageInfo!.appserver.size)
			let appfuture = self.pullSingleImage(pull: apppull, progressHandler: handler)
			appfuture.onSuccess { _ in
				let cpull = DockerPullOperation(baseUrl: self.baseUrl, imageName: "rc2server/compute", estimatedSize: self.imageInfo!.computeserver.size)
				let cfuture = self.pullSingleImage(pull: cpull, progressHandler: handler)
				cfuture.onSuccess { _ in
					promise.success(true)
					}.onFailure { err in
						promise.failure(err)
				}
				}.onFailure { err in
					promise.failure(err)
			}
			}.onFailure { err in
				promise.failure(err)
		}
		return promise.future
	}

	///checks to see if a network with the specified name exists
	public func networkExists(named:String) -> Future<Bool, NSError> {
		precondition(initialzed)
		let promise = Promise<Bool, NSError>()
		dockerRequest("/networks").onSuccess { json in
			promise.success(json.array?.filter({ aNet in
				return aNet["Name"].stringValue == named
			}).count ?? 0 > 0)
		}.onFailure { err in
			promise.failure(err)
		}
		return promise.future
	}
	
	public func createNetwork(named:String) -> Future<Bool, NSError> {
		precondition(initialzed)
		let promise = Promise<Bool, NSError>()
		
		return promise.future
	}
}

//MARK: - Private Methods
fileprivate extension DockerManager {
	///parses the version string from docker rest api
	/// - parameter json: the json returned from the rest call
	/// - returns: nil on success, NSError on failure
	func processVersionJson(json:JSON) -> NSError? {
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
		let url = baseUrl.appendingPathComponent(command)
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

	///requests the list of images from docker and sticks them in installedImages property
	func loadImages() -> Future<[DockerImage],NSError> {
		precondition(initialzed)
		let promise = Promise<[DockerImage],NSError>()
		checkForImageUpdate().onSuccess { _ in
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
	
	///creates AppSupport/io.rc2.xxx/[v1/pgdata, v1/docker-compolse.yml]
	func setupDataDirectory() {
		do {
			let fm = FileManager()
			let appdir = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
			dataDirectory = appdir.appendingPathComponent(Bundle.main.object(forInfoDictionaryKey: "CFBundleIdentifier") as! String, isDirectory: true).appendingPathComponent("v1", isDirectory: true)
			if !fm.directoryExists(at: dataDirectory!) {
				try fm.createDirectory(at: dataDirectory!, withIntermediateDirectories: true, attributes: nil)
			}
			let pgdir = dataDirectory!.appendingPathComponent("pgdata", isDirectory: true)
			if !fm.directoryExists(at: pgdir) {
				try fm.createDirectory(at: pgdir, withIntermediateDirectories: true, attributes: nil)
			}
			let composeurl = Bundle(for: type(of: self)).url(forResource: "docker-compoose", withExtension: "yml")
			assert(composeurl!.fileExists())
			let desturl = dataDirectory!.appendingPathComponent("docker-compose.yml")
			try fm.copyItem(at: composeurl!, to: desturl)
		} catch let err {
			os_log("error setting up data diretory: %{public}s", err as NSError)
		}
		
		
	}
}

