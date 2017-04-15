//
//  DockerManager.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

// TODO: backup database to dataDirectory

import Foundation
import Freddy
import ReactiveSwift
import Result
import ServiceManagement
import os
import SwiftyUserDefaults
import ClientCore

// swiftlint:disable file_length

public enum DockerBackupOption: Int {
	case hourly = 1
	case daily = 0
	case weekly = 2
}

// MARK: UserDefaults support
public extension UserDefaults {
	subscript(key: DefaultsKey<DockerBackupOption>) -> DockerBackupOption {
		get { return unarchive(key) ?? .daily }
		set { archive(key, newValue) }
	}
}

public extension DefaultsKeys {
	public static let lastImageInfoCheck = DefaultsKey<Double>("lastImageInfoCheck")
	public static let cachedImageInfo = DefaultsKey<JSON?>("cachedImageInfo")
	public static let removeOldImages = DefaultsKey<Bool>("dockerRemoveOldImages")
	public static let dockerBackupFrequency = DefaultsKey<DockerBackupOption>("dockerBackupFrequency")
}

enum ManagerState: Int, Comparable {
	case unknown, initialized, ready

	static func < (lhs: ManagerState, rhs: ManagerState) -> Bool {
		return lhs.rawValue < rhs.rawValue
	}
}

let volumeNames = ["rc2_dbdata", "rc2_userlib"]

// MARK: -
/// manages communicating with the local docker engine
public final class DockerManager: NSObject {
	// MARK: - Properties
	let waitingOnContainersTimeout: TimeInterval = 8.0
	/// the containers managed.
	// these should always be referred to as self.containers since many parameters have the name containers
	public fileprivate(set) var containers: [DockerContainer]
	public var isReady: Bool { return state == .ready }

	let sessionConfig: URLSessionConfiguration
	let session: URLSession
	public let api: DockerAPI!
	let networkName = "rc2server"
	let requiredApiVersion = 1.24
	let baseInfoUrl: String
	let defaults: UserDefaults
	/// the base url to connect to. will be set in init, but unwrapped since might be after call to super.init
	fileprivate(set) var baseUrl: URL!
	fileprivate(set) var versionInfo: DockerVersion?
	/// information loaded from baseInfoUrl about what images we should have available
	fileprivate(set) var imageInfo: RequiredImageInfo?
	fileprivate(set) var installedImages: [DockerImage] = []
	fileprivate(set) var pullProgress: PullProgress?
	fileprivate var pullAlreadyDownloaded: Int = 0
	fileprivate(set) var dataDirectory: URL?
	fileprivate let socketPath = "/var/run/docker.sock"
	///the path to use for the source shared folder for dbserver. overridden when using a remote docker daemon
	fileprivate var remoteLocalSharePath: String?
	/// used for time to start listening to events
	private let startupTime = Int(Date.timeIntervalSinceReferenceDate)
	/// monitors event stream
	fileprivate var eventMonitor: DockerEventMonitor?
	private var state: ManagerState = .unknown

	//for dependency injection
	var eventMonitorClass: DockerEventMonitor.Type = DockerEventMonitorImpl.self
	
	#if DEBUG
	private let updateDelay = 60.0 //1 minute
	#else
	private let updateDelay = 86_400.0 //1 day
	#endif
	///has enough time elapsed that we should check to see if there is an update to the docker images
	/// will always return true if the 'SkipUpdateCache' environment variable is set
	public var shouldCheckForUpdate: Bool {
		guard nil == ProcessInfo.processInfo.environment["DMSkipUpdateCache"] else { return true }
		return defaults[.lastImageInfoCheck] + updateDelay <= Date.timeIntervalSinceReferenceDate
	}

	// MARK: - Initialization

	///Default initializer. After creation, initializeConnection or isDockerRunning must be called
	/// - parameter hostUrl: The base url of the docker daemon (i.e. http://localhost:2375/) to connect to. nil means use /var/run/docker.sock. Also checks for the environment variable "DockerHostUrl" if not specified. If DockerHostUrl is specified, also should define DockerHostSharePath as the path to map to /rc2 in the dbserver container
	/// - parameter baseInfoUrl: the base url where imageInfo.json can be found. Defaults to www.rc2.io. Can be overridden by 'ImageInfoBaseUrl' environment variable
	/// - parameter userDefaults: defaults to standard user defaults. Allows for dependency injection.
	/// - parameter sessionConfiguration: url configuration to use, defaults to the standard default configuration
	/// - parameter apiImplementation: the type to use for connections to docker. Allows DI of mock version
	public init(hostUrl host: String? = nil, baseInfoUrl infoUrl: String? = nil, userDefaults: UserDefaults = .standard, sessionConfiguration: URLSessionConfiguration = .default, apiImplementation: DockerAPI.Type = DockerAPIImplementation.self)
	{
		if let hostUrl = host {
			//break down into components
			guard let comps = URLComponents(string: hostUrl) else { fatalError("invalid host string") }
			baseUrl = comps.url!
		} else {
			baseUrl = URL(string: "unix://")
		}
		self.baseInfoUrl = ProcessInfo.processInfo.envValue(name: "ImageInfoBaseUrl", defaultValue: infoUrl == nil ? "https://www.rc2.io/" : infoUrl!)
		defaults = userDefaults
		sessionConfig = sessionConfiguration
		if sessionConfig.protocolClasses?.filter({ $0 == DockerUrlProtocol.self }).count == 0 {
			sessionConfig.protocolClasses = [DockerUrlProtocol.self] as [AnyClass] + sessionConfig.protocolClasses!
		}
		sessionConfig.requestCachePolicy = .reloadIgnoringLocalCacheData
		session = URLSession(configuration: sessionConfig)
		api = apiImplementation.init(baseUrl: baseUrl, sessionConfig: sessionConfig)
		//read image info from defaults
		imageInfo = RequiredImageInfo(from: defaults[.cachedImageInfo])
		containers = []
		super.init()
		assert(baseInfoUrl.hasSuffix("/"))
		let myBundle = Bundle(for: type(of: self))
		//if we have no imageInfo, load from bundled file
		if nil == imageInfo {
			// swiftlint:disable:next force_try (file is in bundle, should never fail)
			let infoData = try! Data(contentsOf: myBundle.url(forResource: "imageInfo", withExtension: "json")!)
			// swiftlint:disable:next force_try
			imageInfo = RequiredImageInfo(from: try! JSON(data: infoData))
			assert(imageInfo != nil)
		}
		setupDataDirectory()
		//check for a host specified as an environment variable - useful for testing
		if nil == host, let envHost = ProcessInfo.processInfo.environment["DockerHostUrl"] {
			//remove any trailing slash as docker doesn't like double slashes in a url
			baseUrl = URL(string: envHost.truncate(string: "/"))
			guard let spath = ProcessInfo.processInfo.environment["DockerHostSharePath"] else {
				fatalError("remote url provided without share path")
			}
			remoteLocalSharePath = spath
		}
		assert(baseUrl != nil, "hostUrl not specified as argument or environment variable")
		//load static docker info we'll use throughout this class
		let path: String = myBundle.path(forResource: "dockerInfo", ofType: "json")!
		let jsonStr = String(data: URL(fileURLWithPath: path).contents()!, encoding: .utf8)!
		guard let containerJson = try? JSON(jsonString: jsonStr) else { fatalError() }
		containers = DockerContainer.fromCreateInfoJson(json: containerJson)
		assert(containers.count == ContainerType.all.count)
	}

	deinit {
		session.invalidateAndCancel()
	}

	// MARK: - standard operating procedure

	/// loads version info from docker daemon and then checks for updates to image info from baseInfoUrl
	///
	/// - parameter refresh: if true, discards any cached info about version and required image info
	///
	/// - returns: a signal producer whose value is true if pullImage is necessary
	public func initialize(refresh: Bool = false) -> SignalProducer<Bool, Rc2Error>
	{
		if refresh {
			state = .unknown
			versionInfo = nil
		}
		os_log("dm.initialize called", log: .docker, type: .debug)
		guard state < .initialized && versionInfo == nil else {
			os_log("dm.initialize already initialized", log: .docker, type: .debug)
			return SignalProducer<Bool, Rc2Error>(value: true)
		}
		let producer = self.api.loadVersion()
			.flatMap(.concat, transform: verifyValidVersion)
			.map { v in
				self.versionInfo = v
				self.state = .initialized
				self.eventMonitor = self.eventMonitorClass.init(baseUrl: self.baseUrl, delegate: self, sessionConfig: self.sessionConfig)
			}
			.flatMap(.concat, transform: validateNetwork)
			.flatMap(.concat, transform: validateVolumes)
			.flatMap(.concat, transform: loadInitialContainerInfo)
			.flatMap(.concat, transform: api.loadImages)
			.map { images in self.installedImages = images; return refresh }
			.flatMap(.concat, transform: checkForImageUpdate)
			.map { _ in
				return self.pullIsNecessary()
			}
		return producer
	}

	/// pulls any images needed from docker hub
	///
	/// - returns: the values are repeated progress handlers
	public func pullImages() -> SignalProducer<PullProgress, Rc2Error>
	{
		precondition(imageInfo != nil)
		precondition(imageInfo!.dbserver.size > 0)
		os_log("dm.pullImages called", log: .docker, type: .debug)
		var fullSize = 0 //imageInfo!.reduce(0) { val, info in val + info.size }
		let producers = imageInfo!.flatMap { img -> SignalProducer<PullProgress, Rc2Error>? in
			os_log("got pull for %{public}@", log:.docker, type:.debug, img.fullName)
			//skip pull if container already using that image
			if let ctype = ContainerType(rawValue: img.name), img.id == containers[ctype]?.imageId ?? "" {
				return nil
			}
			fullSize += img.estSize
			return self.pullSingleImage(pull: DockerPullOperation(imageName: img.fullName, estimatedSize: img.size))
		}
		pullProgress = PullProgress(name: "all", size: fullSize)
		//use concat instead of merge because progress depends on order of download (layer sizes)
		let producer = SignalProducer< SignalProducer<PullProgress, Rc2Error>, Rc2Error >(producers)
		return producer.flatten(.concat)
	}

	/// Ensures docker has the correct containers available and the containers property is in sync with docker
	///
	/// - precondition: initialize() must have been called
	///
	/// - returns: a signal producer with no values
	public func prepareContainers() -> SignalProducer<(), Rc2Error>
	{
		os_log("dm.prepareContainers called", log: .docker, type: .debug)
		return self.api.refreshContainers()
			.on(value: { newContainers in
				//need to set the version used to create our containers from the image info we just processed
				for aType in ContainerType.all {
					newContainers[aType]?.createInfo = self.containers[aType]!.createInfo
					// swiftlint:disable:next force_try
					try! newContainers[aType]?.injectIntoCreate(imageTag: self.imageInfo![aType].fullName)
				}
			})
			.map { newContainers in return (newContainers, self.containers) }
			.flatMap(.concat, transform: mergeContainers)
			.flatMap(.concat, transform: removeOutdatedContainers)
			.flatMap(.concat, transform: createUnavailable)
			.map { _ in }
	}

	// MARK: - possibly public for update management

	/// contacts the baseInfo server to update the image requirements (might be cached)
	///
	/// - parameter forceRefresh: true if any cached information should be discarded
	///
	/// - precondition: initialize() was called
	/// - remark: called as part of initialize() process. Should only call to force an image update check
	///
	/// - returns: a signal producer whose value is true if the imageInfo was updated. If true, then prepareContainers needs to be called to update existing containers
	public func checkForImageUpdate(forceRefresh: Bool = false) -> SignalProducer<Bool, Rc2Error>
	{
		precondition(state >= .initialized)
		os_log("dm.checkForImageUpdate", log: .docker, type: .debug)
		//short circuit if we don't need to check and have valid data
		guard imageInfo == nil || shouldCheckForUpdate || forceRefresh else {
			os_log("skipping imageInfo fetch", log:.docker, type:.info)
			return SignalProducer<Bool, Rc2Error>(value: true)
		}
		return api.fetchJson(url: URL(string:"\(baseInfoUrl)imageInfo.json")!).map { json in
			self.defaults[.lastImageInfoCheck] = Date.timeIntervalSinceReferenceDate
			do {
				let newInfo = try RequiredImageInfo(json: json)
				guard newInfo.newerThan(self.imageInfo) else {
					os_log("dm.checkForImageUpdate: newInfo not newer", log: .docker, type: .debug)
					return false
				}
				self.imageInfo = newInfo
				self.defaults[.cachedImageInfo] = json
			} catch {
				os_log("got imageInfo error: %{public}@", log: .docker, error.localizedDescription)
				return false
			}
			return true
		}.flatMapError  { err in
			os_log("dm.checkForImageUpdate error %{public}@", log: .docker, type: .debug, err as NSError)
			return SignalProducer<Bool, Rc2Error>(value: false)
		}
	}

	/// compares installedImages with imageInfo to see if a pull is necessary
	///
	/// - remark: initialize() returns the same information
	///
	/// - returns: true if there are newer images we need to pull and pullImages() should be called
	public func pullIsNecessary() -> Bool
	{
		//TODO: we need tag/version info as part of the images
		for aTag in [imageInfo!.dbserver.tag, imageInfo!.appserver.tag, imageInfo!.computeserver.tag] {
			if installedImages.filter({ img in img.isNamed(aTag) }).count < 1 {
				return true
			}
		}
		os_log("no pull necessary", log: .docker, type: .info)
		return false
	}

	// MARK: - container operations

	/// Performs an operation on a container
	///
	/// - parameter operation: the operation to perform
	/// - parameter container: the container to perform the operation on
	///
	/// - returns: a signal producer with no values, just completed or error
	public func perform(operation: DockerContainerOperation, on container: DockerContainer) -> SignalProducer<(), Rc2Error>
	{
		return api.perform(operation: operation, container: container)
	}

	/// performs operation on all containers
	///
	/// - parameter operation: the operation to perform
	///
	/// - returns: a signal producer with no value
	public func perform(operation: DockerContainerOperation, on inContainers: [DockerContainer]? = nil) -> SignalProducer<(), Rc2Error>
	{
		var selectedContainers = self.containers
		if inContainers != nil {
			selectedContainers = inContainers!
		}
		return api.perform(operation: operation, containers: selectedContainers)
	}
	
	/// Returns a signal producer that is completed when all containers are running, can timeout with an error
	///
	/// - Returns: signal producer completed when all containers are running
	public func waitUntilRunning() -> SignalProducer<(), Rc2Error>
	{
		os_log("dm.waitUntilRunning called", log: .docker, type: .debug)
		let notRunningContainers = self.containers.filter({ $0.state.value != .running })
		guard notRunningContainers.count > 0 else {
			//short circuit if they all are running
			return SignalProducer<(), Rc2Error>(value: ())
		}
		//need to listen to all container signals that aren't running
		let timeoutError = Rc2Error(type: .docker, explanation: "timed out waiting for containers to start")
		//map container(s) to a producer that completes when the container's state changes to .running
		let producers = notRunningContainers.map { aContainer in
			aContainer.state.producer.filter({ $0 == .running })
				.take(first: 1)
				.timeout(after: waitingOnContainersTimeout, raising: timeoutError, on: QueueScheduler.main)
		}
		let combined: SignalProducer< SignalProducer<ContainerState, Rc2Error>, Rc2Error> = SignalProducer(producers)
		//return a producer that will listen until all containers are running and then send a completed, timing out if doesn't happen
		return combined
			.flatten(.merge)
			.collect()
			.map { _ in return () }
			.optionalLog("waitUntilRunning")
			.observe(on: UIScheduler())
	}
	
	/// backs up the dbserver database to the specified file location
	///
	/// - Parameter url: path to save the file to
	/// - Returns: a signal producer with an empty value, or an error
	public func backupDatabase(to url: URL) -> SignalProducer<(), Rc2Error>
	{
		let command = ["/usr/bin/pg_dump", "rc2"]
		return api.execCommand(command: command, container: containers[.dbserver]!)
			.flatMap(.concat) { data -> SignalProducer<(), Rc2Error> in
				do {
					try data.write(to: url)
				} catch {
					let rc2err = Rc2Error(type: .file, nested: error, explanation: "failed to write backup file")
					return SignalProducer<(), Rc2Error>(error: rc2err)
				}
				return SignalProducer<(), Rc2Error>(value: ())
			}
	}
}

// MARK: - Event Monitor Delegate
extension DockerManager: DockerEventMonitorDelegate {
	/// handles an event from the event monitor
	// note that the only events that external observers should care about (as currently implemented) are related to specific containers, which will update their observable state property. Probably need a way to inform application if some serious problem ocurred
	func handleEvent(_ event: DockerEvent)
	{
		//only care if it is one of our containers
		guard let from = try? event.json.getString(at:"from"),
			let ctype = ContainerType.from(imageName:from),
			let container = self.containers[ctype] else { return }
		switch event.eventType {
			case .die:
				os_log("warning: container died: %{public}@", log:.docker, from as String)
				if let exitStatusStr = try? event.json.getString(at: "exitCode"),
					let exitStatus = Int(exitStatusStr), exitStatus != 0
				{
					//abnormally died
					//TODO: handle abnormal death of container
					os_log("warning: container %{public}@ died with non-normal exit code", log:.docker, ctype.rawValue as String)
				}
				container.update(state: .exited)
			case .start:
				container.update(state: .running)
			case .pause:
				container.update(state: .paused)
			case .unpause:
				container.update(state: .running)
			case .destroy:
				os_log("one of our containers was destroyed", log:.docker, type:.error)
				//TODO: need to handle container being destroyed
			case .deleteImage:
				os_log("one of our images was deleted", log:.docker, type:.error)
				//TODO: need to handle image being deleted
			default:
				break
		}
	}

	func eventMonitorClosed(error: Error?)
	{
		eventMonitor = nil
		//TODO: actually handle by reseting everything related to docker
		os_log("event monitor closed. should really do something", log:.docker)
	}
}

// MARK: - Private Methods
extension DockerManager {
	/// Validates the version parameter meets requirements.
	///
	/// - parameter version: the version information to check
	///
	/// - returns: a signal producer whose value is the valid version info
	func verifyValidVersion(version: DockerVersion) -> SignalProducer<DockerVersion, Rc2Error>
	{
		return SignalProducer<DockerVersion, Rc2Error> { observer, _ in
			//force cast because only should be called if versionInfo was set
			os_log("dm.verifyValidVersion: %{public}@", log: .docker, type: .debug, version.description)
			if version.apiVersion >= self.requiredApiVersion {
				self.versionInfo = version
				observer.send(value: version)
				observer.sendCompleted()
			} else {
				os_log("dm unsupported docker version", log: .docker, type: .default)
				observer.send(error: Rc2Error(type: .docker, nested: DockerError.unsupportedDockerVersion))
			}
		}
	}

	fileprivate func validateNetwork() -> SignalProducer<(), Rc2Error>
	{
		let nname = "rc2server"
		return api.networkExists(name: nname)
			.map { exists in return (nname, exists, self.api.create(network:)) }
			.flatMap(.concat, transform: optionallyCreateObject)
	}

	fileprivate func validateVolumes() -> SignalProducer<(), Rc2Error>
	{
		let producers = volumeNames.map { name in
			api.volumeExists(name: name)
				.map { exists in return (name, exists, self.api.create(volume:)) }
				.flatMap(.concat, transform: optionallyCreateObject)
		}
		let combinedProducer = SignalProducer< SignalProducer<(), Rc2Error>, Rc2Error >(producers)
		return combinedProducer.flatten(.merge)
			.collect()
			.map { _ in return () }
			.optionalLog("combined vols")
	}

	// first check of containers, before images are loaded
	fileprivate func loadInitialContainerInfo() -> SignalProducer<(), Rc2Error>
	{
		let producer = self.api.refreshContainers()
			.on(value: { newContainers in
				//need to set the version used to create our containers from the image info we just processed
				for aType in ContainerType.all {
					newContainers[aType]?.createInfo = self.containers[aType]!.createInfo
					// swiftlint:disable:next force_try
					try! newContainers[aType]?.injectIntoCreate(imageTag: self.imageInfo![aType].fullName)
				}
			})
			.map { newContainers in return (newContainers, self.containers) }
			.flatMap(.concat, transform: mergeContainers)
			.map { _ in return () }
		return producer
	}
	
	typealias CreateFunction = (String) -> SignalProducer<(), Rc2Error>

	fileprivate func optionallyCreateObject(name: String, exists: Bool, handler: CreateFunction) -> SignalProducer<(), Rc2Error>
	{
		guard !exists else {
			return SignalProducer<(), Rc2Error>(value: ())
		}
		return handler(name)
	}

	/// Creates any containers that don't exist
	///
	/// - parameter containers: the containers to create if necessary
	///
	/// - returns: the containers unchanged
	fileprivate func createUnavailable(containers: [DockerContainer]) -> SignalProducer<[DockerContainer], Rc2Error>
	{
		os_log("dm.createUnavailable called", log: .docker, type: .debug)
		for aType in ContainerType.all {
			// swiftlint:disable:next force_try
			try! containers[aType]?.injectIntoCreate(imageTag: self.imageInfo![aType].fullName)
		}
		let producers = containers.map { self.api.create(container: $0) }
		return SignalProducer.merge(producers).collect()
	}

	/// Remove any containers whose images are outdated
	///
	/// Parameter containers: the containers to examine
	/// - Returns: a merged array of signal producers that returns the input containers with their state updated
	func removeOutdatedContainers(containers: [DockerContainer]) -> SignalProducer<[DockerContainer], Rc2Error>
	{
		os_log("dm.removeOutdatedContainers called", log: .docker, type: .debug)
		var containersToRemove = [DockerContainer]()
		for aContainer in containers {
			let image = imageInfo![aContainer.type]
			if image.id != aContainer.imageId && aContainer.state.value != .notAvailable {
				os_log("outdated image for %{public}@", log: .docker, type: .info, aContainer.type.rawValue as String)
				containersToRemove.append(aContainer)
			}
		}
		guard containersToRemove.count > 0 else {
			return SignalProducer<[DockerContainer], Rc2Error>(value: containers)
		}
		var producers = [SignalProducer<(), Rc2Error>]()
		containersToRemove.forEach { aContainer in
			if aContainer.state.value == .running {
				producers.append(api.perform(operation: .stop, container: aContainer))
			}
			producers.append(api.remove(container: aContainer).on(completed: {
				aContainer.update(state: .notAvailable)
			}))
		}
		let combinedProducer = SignalProducer< SignalProducer<(), Rc2Error>, Rc2Error >(producers)
		//combinedProducers will produce no values. Need to folow with a second producer that returns the containers as a value
		return combinedProducer.flatten(.concat).then(SignalProducer<[DockerContainer], Rc2Error>(value: containers))
	}
	
	/// Updates the containers property to match the information in the containers parameter
	///
	/// - remark: possible side-effects since DockerContainers are a class not a value-type
	/// - Parameter containers: containers array from docker
	///
	/// - returns: a signal producer whose value is oldContainers updated to newContainers
	func mergeContainers(newContainers: [DockerContainer], oldContainers: [DockerContainer]) -> SignalProducer<[DockerContainer], Rc2Error>
	{
		return SignalProducer<[DockerContainer], Rc2Error> { observer, _ in
			os_log("dm.mergeContainers called", log: .docker, type: .debug)
			oldContainers.forEach { aContainer in
				if let c2 = newContainers[aContainer.type] {
					aContainer.update(from: c2)
				}
			}
			DispatchQueue.global().async {
				observer.send(value: oldContainers)
				observer.sendCompleted()
			}
		}
	}

	//for now maps promise/future pull operation to a signal producer
	func pullSingleImage(pull: DockerPullOperation) -> SignalProducer<PullProgress, Rc2Error>
	{
		os_log("dm.pullSingleImage called for %{public}@", log: .docker, type: .debug, pull.pullProgress.name)
		pullProgress?.extracting = false
 		var lastValue: Int = 0
		return pull.pull().map { pp in
			var npp = PullProgress(name: pp.name, size: self.pullProgress!.estSize)
			npp.currentSize = pp.currentSize + self.pullAlreadyDownloaded
			lastValue = pp.currentSize
			return npp
		}.on(completed: {
			self.pullAlreadyDownloaded += lastValue
			lastValue = 0
		})
	}

	///creates AppSupport/io.rc2.xxx/v1/dbdata
	func setupDataDirectory()
	{
		do {
			let dockerDir = try AppInfo.subdirectory(type: .applicationSupportDirectory, named: "docker")
			let fm = FileManager()
			let pgdir = dockerDir.appendingPathComponent("dbdata", isDirectory: true)
			if !fm.directoryExists(at: pgdir) {
				try fm.createDirectory(at: pgdir, withIntermediateDirectories: true, attributes: nil)
			}
		} catch let err {
			os_log("error setting up data diretory: %{public}@", log:.docker, err as NSError)
		}
	}
}
