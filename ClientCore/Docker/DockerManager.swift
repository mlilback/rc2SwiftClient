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
/// simple operations that can be performed on a container
public enum ContainerOperation: String {
	case start, stop, restart, pause, resume = "unpause"
}

//MARK: -
///manages communicating with the local docker engine
open class DockerManager : NSObject {
	//MARK: - Properties
	let dockerLog = OSLog(subsystem: "io.rc2.client", category: "docker")
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
	public let containers: [DockerContainer]
	fileprivate(set) var pullProgress: PullProgress?
	fileprivate(set) var dataDirectory:URL?
	fileprivate let socketPath = "/var/run/docker.sock"
	fileprivate var initialzed = false
	fileprivate var versionLoaded:Bool = false
	///the path to use for the source shared folder for dbserver. overridden when using a remote docker daemon
	fileprivate var remoteLocalSharePath: String?
	/// used for time to start listening to events
	private let startupTime = Int(Date.timeIntervalSinceReferenceDate)
	/// monitors event stream
	fileprivate var eventMonitor: DockerEventMonitor?
	
	///has enough time elapsed that we should check to see if there is an update to the docker images
	public var shouldCheckForUpdate: Bool {
		return defaults[.lastImageInfoCheck] + 86400.0 <= Date.timeIntervalSinceReferenceDate
	}
	
	//MARK: - Initialization
	
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
		containers = [DockerContainer(type:.dbserver), DockerContainer(type:.appserver), DockerContainer(type:.compute)]
		super.init()
		isInstalled = Foundation.FileManager().fileExists(atPath: socketPath)
		setupDataDirectory()
		//check for a host specified as an environment variable - useful for testing
		if nil == host, var envHost = ProcessInfo.processInfo.environment["DockerHostUrl"] {
			//go through a lot of trouble to remove any trailing slash
			if envHost.hasSuffix("/") {
				envHost = envHost.substring(to: envHost.index(envHost.endIndex, offsetBy: -1))
			}
			baseUrl = URL(string:envHost)
			guard let spath = ProcessInfo.processInfo.environment["DockerHostSharePath"] else {
				fatalError("remote url provided without share path")
			}
			remoteLocalSharePath = spath
		}
		assert(baseUrl != nil, "hostUrl not specified as argument or environment variable")
		//load static docker info we'll use throughout this class
		let path : String = Bundle(for:type(of: self)).path(forResource: "dockerInfo", ofType: "json")!
		let containerInfo = JSON(data: try! Data(contentsOf: URL(fileURLWithPath: path)))
		assert(containerInfo.dictionary?.count == ContainerType.all.count)
		for aContainer in containers {
			aContainer.createInfo = containerInfo[aContainer.type.rawValue]
		}
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
	
	/// Loads basic version information from the docker daemon. Also loads list of docker images that are installed and gets info for existing containers.
	/// Must be called before being using any func except isDockerRunning().
	/// - returns: future. the result will be false if there was an error parsing information from docker.
	public func initializeConnection() -> DockerFuture {
		self.initialzed = true
		let promise = DockerPromise()
		//if we've already loaded the version info, don't do so again
		guard !versionLoaded else { promise.success(apiVersion > 0); return promise.future }
		let future = dockerRequest("/version")
		future.onSuccess { json in
			if let err = self.processVersionJson(json: json) {
				promise.failure(err)
			} else {
				self.eventMonitor = DockerEventMonitor(baseUrl: self.baseUrl, delegate: self, sessionConfig: self.sessionConfig)
				//successfully parsed the version info. now get the image info
				[self.loadImages(), self.refreshContainers()].sequence().onSuccess { _ in
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
	
	/// Ensures containers exist and are ready to run
	///
	/// - returns: a future whose value will always be true
	public func prepareToStart() -> DockerFuture {
		precondition(initialzed)
		let promise = DockerPromise()
		refreshContainers().onSuccess { _ in
			promise.success(true)
			}.onFailure { err in
				promise.failure(err)
		}
		return promise.future
	}
	
	//MARK: - Image Manipulation
	///Checks to see if it is necessary to check for an imageInfo update, and if so, perform that check.
	/// - returns: a future whose success will be true if a pull is required
	public func checkForImageUpdate() -> DockerFuture {
		precondition(initialzed)
		let promise = DockerPromise()
		//short circuit if we don't need to chedk and have valid data
		guard imageInfo == nil || shouldCheckForUpdate else {
			os_log("using cached docker info", log:dockerLog, type:.info)
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
		os_log("no pull necessary", log:dockerLog, type:.info)
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

	//MARK: - Container operations
	
	/// performs an action on all containers
	///
	/// - parameter operation: the operation to perform
	///
	/// - returns: a future whose value will always be true
	public func performOnAllContainers(operation: ContainerOperation) -> DockerFuture {
		precondition(initialzed)
		let promise = DockerPromise()
		let seq = containers.map { perform(operation:operation, on:$0) }
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
	public func perform(operation:ContainerOperation, on container:DockerContainer) -> DockerFuture {
		precondition(initialzed)
		let promise = DockerPromise()
		let url = baseUrl.appendingPathComponent("/containers/\(container.name)/\(operation.rawValue)")
		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		session.dataTask(with: request, completionHandler: { (data, response, error) in
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

	/// removes a container. perform() only works on GET requests, this is a DELETE request
	///
	/// - parameter container: container to remove
	///
	/// - returns: a future whose value will always be true
	public func remove(container:DockerContainer) -> DockerFuture {
		precondition(initialzed)
		let promise = DockerPromise()
		let url = baseUrl.appendingPathComponent("/containers/\(container.name)")
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
		let seq = containers.map { remove(container: $0) }
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
		//should never error since object is a constant
		let filtersJson = try! JSONSerialization.data(withJSONObject: ["label": ["rc2.live"]], options: [])
		let filtersStr = String(data:filtersJson, encoding:.utf8)!
		var urlcomponents = URLComponents(url: baseUrl.appendingPathComponent("/containers/json"), resolvingAgainstBaseURL: true)!
		urlcomponents.queryItems = [URLQueryItem(name:"all", value:"1"), URLQueryItem(name:"filters", value:filtersStr)]
		makeRequest(request: URLRequest(url: urlcomponents.url!)).onSuccess { rawData in
			let jsonStr = String(data:rawData, encoding:.utf8)!
			let json = JSON.parse(jsonStr)
			if json == JSON.null {
				promise.failure(NSError.error(withCode: .invalidJson, description: "invalid json for list containers"))
			} else {
				for entry in json.arrayValue {
					if let type = ContainerType.from(imageName: entry["Image"].stringValue) {
						do {
							try self.containers[type]?.update(json:entry)
						} catch let err {
							os_log("error updating container: %{public}s", log:self.dockerLog, type:.error, err as NSError)
						}
					}
				}
				return promise.success(true)
			}
		}.onFailure { err in
			promise.failure(err)
		}
		return promise.future
	}
	
	//MARK: - Network operations
	
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
				os_log("upload request received strange response", log:self.dockerLog, type:.error)
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

//MARK: - Event Monitor Delegate
extension DockerManager: DockerEventMonitorDelegate {
	func handleEvent(_ event: DockerEvent) {
		os_log("got event: %{public}s", log:dockerLog, type:.info, event.description)
		print("got event: \(event)")
		//only care if it is one of our containers
		guard let from = event.json["from"].string,
			let ctype = ContainerType.from(imageName:from),
			let container = containers[ctype] else { return }
		switch event.eventType {
			case .die:
				os_log("warning: container died: %{public}s", log:dockerLog, from)
				if let exitStatusStr = event.json["exitCode"].string, let exitStatus = Int(exitStatusStr), exitStatus != 0
				{
					//abnormally died
					//TODO: handle abnormal death of container
					os_log("warning: container %{public}s died with non-normal exit code", log:dockerLog, ctype.rawValue)
				}
				container.update(state: .exited)
			case .start:
				os_log("container %{public}s started", log:dockerLog, from)
				container.update(state: .running)
			case .pause:
				container.update(state: .paused)
			case .unpause:
				container.update(state: .running)
			case .destroy:
				os_log("one of our containers was destroyed", log:dockerLog, type:.error)
				//TODO: need to handle container being destroyed
			case .deleteImage:
				os_log("one of our images was deleted", log:dockerLog, type:.error)
				//TODO: need to handle image being deleted
			default:
				break
		}
	}
	
	func eventMonitorClosed(error: Error?) {
		eventMonitor = nil
		//TODO: actually handle by reseting everything related to docker
		os_log("event monitor closed. should really do something", log:dockerLog)
	}
}

//MARK: - Private Methods
fileprivate extension DockerManager {
	/// Load any containers who are .notAvailable
	///
	/// - returns: a future whose value will always be true
	func initializeContainers() -> DockerFuture {
		precondition(initialzed)
		let promise = DockerPromise()
		var futures:[DockerFuture] = []
		for aContainer in containers {
			if aContainer.state.value == .notAvailable {
				futures.append(create(container:aContainer))
			}
		}
		guard futures.count > 0 else {
			promise.success(true)
			return promise.future
		}
		//we need to run them
		futures.sequence().onSuccess { _ in
			promise.success(true)
			}.onFailure { err in
				promise.failure(err)
		}
		return promise.future
	}
	
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
				os_log("failed to parser version string", log:dockerLog, type:.info)
			}
			self.apiVersion = Double(json["ApiVersion"].stringValue)!
			os_log("docker is version %d.%d.%d:%d", log:dockerLog, type:.info, self.primaryVersion, self.secondaryVersion, self.fixVersion, self.apiVersion)
			return nil
		} catch let err as NSError {
			os_log("error getting docker version %{public}@", log:dockerLog, type:.error, err)
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
			guard let rawData = data, let rsp = response as? HTTPURLResponse, error == nil else {
				promise.failure(error as! NSError)
				return
			}
			guard rsp.statusCode == 200 else {
				let httperror = NSError.error(withCode: .serverError, description: "server returned \(rsp.statusCode) error", underlyingError: error as NSError?)
				promise.failure(httperror)
				return
			}
			promise.success(rawData)
		}).resume()
		return promise.future
	}

	///requests the list of images from docker and sticks them in installedImages property
	func loadImages() -> DockerFuture {
		precondition(initialzed)
		let promise = DockerPromise()
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
				promise.success(true)
				
			}.onFailure { err in
				os_log("error reading image data from docker: %{public}s", log:self.dockerLog, type:.error, err)
				promise.failure(err)
			}
		}.onFailure { err in
			promise.failure(err)
		}
		return promise.future
	}
	
	/// creates a container on the docker daemon. containers property is not updated with the new container
	/// - parameter container: which container to create
	/// - returns: future whose value will always be true
	func create(container:DockerContainer) -> DockerFuture
	{
		precondition(initialzed)
		precondition(container.state.value == .notAvailable)
		let promise = DockerPromise()
		var containerJson = container.createInfo!
		containerJson["Labels"] = JSON(["rc2.live": ""])
		if case .dbserver = container.type {
			var pgdir = dataDirectory!.appendingPathComponent("dbdata", isDirectory: true).standardizedFileURL.path
			//if we are connecting to a remote docker host, can't use a local folder for the share path
			if let remotePath = remoteLocalSharePath {
				pgdir = remotePath
			}
			containerJson["Binds"] = JSON(["\(pgdir):/rc2"])
		}
		let jsonData = try! containerJson.rawData()
		var comps = URLComponents(url: URL(string:"/containers/create", relativeTo:baseUrl)!, resolvingAgainstBaseURL: true)!
		comps.queryItems = [URLQueryItem(name:"name", value:container.name)]
		var request = URLRequest(url: comps.url!)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
				promise.failure(NSError.error(withCode: .alreadyExists, description: "container \(container.type.rawValue) already exists"))
			default:
				let errStr = String(data:data!, encoding:.utf8)!
				promise.failure(NSError.error(withCode: .serverError, description: "server returned \(statusCode):\(errStr)"))
			}
		}
		task.resume()
		return promise.future
	}
	
	///creates AppSupport/io.rc2.xxx/[v1/dbdata, v1/docker-compolse.yml]
	func setupDataDirectory() {
		do {
			let fm = FileManager()
			let appdir = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
			let bundleId = AppInfo.bundleIdentifier ?? "io.rc2.Client"
			dataDirectory = appdir.appendingPathComponent(bundleId, isDirectory: true).appendingPathComponent("v1", isDirectory: true)
			if !fm.directoryExists(at: dataDirectory!) {
				try fm.createDirectory(at: dataDirectory!, withIntermediateDirectories: true, attributes: nil)
			}
			let pgdir = dataDirectory!.appendingPathComponent("dbdata", isDirectory: true)
			if !fm.directoryExists(at: pgdir) {
				try fm.createDirectory(at: pgdir, withIntermediateDirectories: true, attributes: nil)
			}
//			let composeurl = Bundle(for: type(of: self)).url(forResource: "docker-compose", withExtension: "yml")
//			assert(composeurl!.fileExists())
//			let desturl = dataDirectory!.appendingPathComponent("docker-compose.yml")
//			try fm.copyItem(at: composeurl!, to: desturl)
		} catch let err {
			os_log("error setting up data diretory: %{public}s", log:dockerLog, err as NSError)
		}
		
		
	}
}

