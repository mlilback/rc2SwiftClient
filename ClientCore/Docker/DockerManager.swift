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

/// a callback closure
public typealias SimpleServerCallback = (_ success:Bool, _ error:NSError?) -> Void
/// alias for future returned
public typealias DockerFuture = Future<Bool, NSError>
///alias for promise used for DockerFuture
typealias DockerPromise = Promise<Bool, NSError>

//MARK: Keys for UserDefaults
extension DefaultsKeys {
	static let lastImageInfoCheck = DefaultsKey<Double>("lastImageInfoCheck")
	static let dockerImageVersion = DefaultsKey<Int>("dockerImageVersion")
	static let cachedImageInfo = DefaultsKey<JSON?>("cachedImageInfo")
}

//MARK: -
/// An enumeration of the container names used to provide services via Docker
public enum Rc2Container: String {
	case dbserver, appserver, compute
}

//MARK: -
/// simple operations that can be performed on a container
public enum ContainerOperation: String {
	case start, stop, restart, pause, resume
}

//MARK: -
///manages communicating with the local docker engine
open class DockerManager : NSObject {
	//MARK: - Properties
	let networkName = "rc2server"
	let requiredApiVersion = 1.24
	public let sessionConfig: URLSessionConfiguration
	public let session: URLSession
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
	fileprivate(set) var containers: [DockerContainer] = []
	fileprivate(set) var pullProgress: PullProgress?
	fileprivate(set) var dataDirectory:URL?
	fileprivate let socketPath = "/var/run/docker.sock"
	fileprivate var initialzed = false
	fileprivate var versionLoaded:Bool = false
	///will be set in init, but unwrapped since might be after call to super.init
	fileprivate var containerInfo: JSON!
	///the path to use for the source shared folder for dbserver. overridden when using a remote docker daemon
	fileprivate var remoteLocalSharePath: String?
	
	///has enough time elapsed that we should check to see if there is an update to the docker images
	public var shouldCheckForUpdate: Bool {
		return defaults[.lastImageInfoCheck] + 86400.0 <= Date.timeIntervalSinceReferenceDate
	}
	
	//MARK: - Public Methods
	
	///Default initializer. After creation, initializeConnection or isDockerRunning must be called
	/// - parameter hostUrl: The base url of the docker daemon (i.e. http://localhost:2375/) to connect to. nil means use /var/run/docker.sock. Also checks for the environment variable "DockerHostUrl" if not specified. If DockerHostUrl is specified, also should define DockerHostSharePath as the path to map to /rc2 in the dbserver container
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
		setupDataDirectory()
		//check for a host specified as an environment variable - useful for testing
		if nil == host, let envHost = ProcessInfo.processInfo.environment["DockerHostUrl"] {
			baseUrl = URL(string:envHost)
			remoteLocalSharePath = ProcessInfo.processInfo.environment["DockerHostSharePath"]
		}
		assert(baseUrl != nil, "hostUrl not specified as argument or environment variable")
		//load static docker info we'll use throughout this class
		let path : String = Bundle(for:type(of: self)).path(forResource: "dockerInfo", ofType: "json")!
		containerInfo = JSON(data: try! Data(contentsOf: URL(fileURLWithPath: path)))
		assert(containerInfo.dictionary?.count == 3)
	}
	
	///connects to the docker daemon and confirms it is running and meets requirements.
	/// calls initializeConnection()
	/// - returns: Closure called with true if able to connect to docker daemon.
	public func isDockerRunning() -> DockerFuture {
		guard initialzed else { return initializeConnection() }
		let promise = DockerPromise()
		promise.success(true)
		return promise.future
	}
	
	///Loads basic version information from the docker daemon. Also loads list of docker images that are installed.
	///Must be called before being using any func except isDockerRunning().
	/// - returns: future. the result will be false if there was an error parsing information from docker.
	public func initializeConnection() -> DockerFuture {
		self.initialzed = true
		let promise = DockerPromise()
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
	public func checkForImageUpdate() -> DockerFuture {
		precondition(initialzed)
		let promise = DockerPromise()
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
	public func pullImages(handler: PullProgressHandler? = nil) -> DockerFuture {
		precondition(imageInfo != nil)
		precondition(imageInfo!.dbserver.size > 0)
		let promise = DockerPromise()
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

	/// performs an action on all containers
	///
	/// - parameter operation: the operation to perform
	///
	/// - returns: a future whose value will always be true
	public func performOnAllContainers(operation: ContainerOperation) -> DockerFuture {
		let promise = DockerPromise()
		let seq = [perform(operation:operation, on:.compute), perform(operation:operation, on:.appserver), perform(operation:operation, on:.dbserver)]
		seq.sequence().onSuccess { _ in
			promise.success(true)
		}.onFailure { err in
			promise.failure(err)
		}
		return promise.future
	}
	
	/// Performs an operation on a docker container
	///
	/// - parameter operation: the operation to perform
	/// - parameter container: the target container
	///
	/// - returns: a future whose value will always be true
	public func perform(operation:ContainerOperation, on container:Rc2Container) -> DockerFuture {
		precondition(initialzed)
		let promise = DockerPromise()
		let url = baseUrl.appendingPathComponent("/containers/\(container.rawValue)/\(operation.rawValue)")
		session.dataTask(with: url, completionHandler: { (data, response, error) in
			guard let hresponse = response as? HTTPURLResponse , error == nil else {
				promise.failure(error as! NSError)
				return
			}
			switch hresponse.statusCode {
				case 204:
					promise.success(true)
				case 304:
					promise.failure(NSError.error(withCode: .alreadyExists, description: "operation already in progress"))
				case 404:
					promise.failure(NSError.error(withCode: .noSuchObject, description: "no such container"))
				default:
					promise.failure(NSError.error(withCode: .serverError	, description: "unknown error"))
			}
		}).resume()
		return promise.future
	}

	/// removes a container
	///
	/// - parameter container: container to remove
	///
	/// - returns: a future whose value will always be true
	public func remove(container:Rc2Container) -> DockerFuture {
		precondition(initialzed)
		let promise = DockerPromise()
		let url = baseUrl.appendingPathComponent("/containers/\(container.rawValue)")
		var request = URLRequest(url: url)
		request.httpMethod = "DELETE"
		session.dataTask(with: request, completionHandler: { (data, response, error) in
			guard let hresponse = response as? HTTPURLResponse , error == nil else {
				promise.failure(error as! NSError)
				return
			}
			switch hresponse.statusCode {
			case 204:
				promise.success(true)
			case 404:
				promise.failure(NSError.error(withCode: .noSuchObject, description: "no such container"))
			default:
				promise.failure(NSError.error(withCode: .serverError	, description: "unknown error"))
			}
		}).resume()
		return promise.future
	}

	/// removes all containers
	///
	/// - returns: a future whose value will always be true
	public func removeAllContainers() -> DockerFuture {
		precondition(initialzed)
		let promise = DockerPromise()
		let seq = [remove(container:.compute), remove(container:.appserver), remove(container:.dbserver)]
		seq.sequence().onSuccess { _ in
			promise.success(true)
		}.onFailure { err in
				promise.failure(err)
		}
		return promise.future
	}

	/// Refreshes the containers property from the docker daemon
	///
	/// - returns: a future whose value will always be true
	public func refreshContainers() -> DockerFuture {
		precondition(initialzed)
		let promise = DockerPromise()
		let filtersJson = JSON(["label": ["rc2.live"]])
		let filtersStr = filtersJson.description.stringByAddingPercentEncodingForFormData()
		var urlcomponents = URLComponents(url: baseUrl.appendingPathComponent("/containers/json"), resolvingAgainstBaseURL: true)!
		urlcomponents.queryItems = [URLQueryItem(name:"all", value:"1"), URLQueryItem(name:"filters", value:filtersStr)]
		makeRequest(request: URLRequest(url: urlcomponents.url!)).onSuccess { rawData in
			let json = JSON(data:rawData)
			if json == JSON.null {
				promise.failure(NSError.error(withCode: .invalidJson, description: "invalid json for list containers"))
			} else {
				self.containers = json.arrayValue.flatMap { DockerContainer(json:$0) }
				guard self.containers.count == json.arrayValue.count else {
					return promise.failure(NSError.error(withCode: .invalidJson, description: "invalid json for list containers"))
				}
				return promise.success(true)
			}
		}.onFailure { err in
			promise.failure(err)
		}
		return promise.future
	}
	
	/// creates a container on the docker daemon. containers property is not updated with the new container
	/// - parameter container: which container to create
	/// - returns: future whose value will always be true
	public func createContainer(_ container:Rc2Container) -> DockerFuture
	{
		precondition(initialzed)
		let promise = DockerPromise()
		var containerJson = containerInfo[container.rawValue]
		containerJson["Labels"] = JSON([["rc2.live": ""]])
		if case .dbserver = container {
			var pgdir = dataDirectory!.appendingPathComponent("dbdata", isDirectory: true).standardizedFileURL.path
			//if we are connecting to a remote docker host, can't use a local folder for the share path
			if let remotePath = remoteLocalSharePath {
				pgdir = remotePath
			}
			containerJson["Binds"] = JSON(["\(pgdir):/rc2"])
		}
		let jsonData = try! containerJson.rawData()
		var comps = URLComponents(url: URL(string:"/containers/create", relativeTo:baseUrl)!, resolvingAgainstBaseURL: true)!
		comps.queryItems = [URLQueryItem(name:"name", value:"rc2_\(container.rawValue)")]
		let request = URLRequest(url: comps.url!)
		let task = session.uploadTask(with: request, from: jsonData) { (data, response, error) in
			guard nil == error else {
				promise.failure(error! as NSError)
				return
			}
			let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 500
			switch statusCode {
				case 201: //success
					promise.success(true)
				case 409:
					promise.failure(NSError.error(withCode: .alreadyExists, description: "container \(container.rawValue) already exists"))
				default:
					promise.failure(NSError.error(withCode: .serverError, description: "server returned \(statusCode)"))
			}
		}
		task.resume()
		return promise.future
	}
	
	///checks to see if a network with the specified name exists
	public func networkExists(named:String) -> DockerFuture {
		precondition(initialzed)
		let promise = DockerPromise()
		dockerRequest("/networks").onSuccess { json in
			promise.success(json.array?.filter({ aNet in
				return aNet["Name"].stringValue == named
			}).count ?? 0 > 0)
		}.onFailure { err in
			promise.failure(err)
		}
		return promise.future
	}
	
	/// sends a request to docker to create a network
	///
	/// - parameter named: the name of the network to create
	///
	/// - returns: a future for the success of the operation
	public func createNetwork(named:String) -> DockerFuture {
		precondition(initialzed)
		let promise = DockerPromise()
		var props = [String:Any]()
		props["Internal"] = true
		props["Driver"] = "bridge"
		props["Name"] = named
		let jsonData = try! JSONSerialization.data(withJSONObject: props, options: [])
		let request = URLRequest(url: URL(string: "/networks/create", relativeTo: baseUrl)!)
		let task = session.uploadTask(with: request, from: jsonData) { (data, response, error) in
			guard error == nil else {
				promise.failure(NSError.error(withCode: .serverError, description: "failed to create network", underlyingError: error as? NSError))
				return
			}
			guard let httpResponse = response as? HTTPURLResponse else {
				os_log("upload request received strange response", type:.error)
				promise.failure(NSError.error(withCode: .impossible, description: "invalid response"))
				return
			}
			guard httpResponse.statusCode == 201 else {
				promise.failure(NSError.error(withCode: .serverError, description: "failed to create network (\(httpResponse.statusCode))"))
				return
			}
			promise.success(true)
		}
		task.resume()
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
	
	func pullSingleImage(pull:DockerPullOperation, progressHandler:PullProgressHandler?) -> DockerFuture
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
	
	/// make a request and return the returned data
	/// - parameter url: The URL to fetch
	/// - returns: a future for the data at url or an error
	func makeRequest(url:URL) -> Future<Data,NSError> {
		return makeRequest(request: URLRequest(url: url))
	}

	/// make a request and return the returned data
	/// - parameter request: The URLRequest to fetch
	/// - returns: a future for the data from request or an error
	func makeRequest(request:URLRequest) -> Future<Data,NSError> {
		let promise = Promise<Data,NSError>()
		session.dataTask(with: request, completionHandler: { (data, response, error) in
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
	
	///creates AppSupport/io.rc2.xxx/[v1/dbdata, v1/docker-compolse.yml]
	func setupDataDirectory() {
		do {
			let fm = FileManager()
			let appdir = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
			dataDirectory = appdir.appendingPathComponent(Bundle.main.object(forInfoDictionaryKey: "CFBundleIdentifier") as! String, isDirectory: true).appendingPathComponent("v1", isDirectory: true)
			if !fm.directoryExists(at: dataDirectory!) {
				try fm.createDirectory(at: dataDirectory!, withIntermediateDirectories: true, attributes: nil)
			}
			let pgdir = dataDirectory!.appendingPathComponent("dbdata", isDirectory: true)
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

