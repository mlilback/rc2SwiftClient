//
//  DockerManager.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

// TODO: backup database to dataDirectory

import Foundation
import Freddy
import BrightFutures
import ReactiveSwift
import Result
import ServiceManagement
import os
import SwiftyUserDefaults
import ClientCore

// MARK: Keys for UserDefaults
extension DefaultsKeys {
	static let lastImageInfoCheck = DefaultsKey<Double>("lastImageInfoCheck")
	static let dockerImageVersion = DefaultsKey<Int>("dockerImageVersion")
	static let cachedImageInfo = DefaultsKey<JSON?>("cachedImageInfo")
}

enum ManagerState: Int, Comparable {
	case unknown, initialized, ready

	static func < (lhs: ManagerState, rhs: ManagerState) -> Bool {
		return lhs.rawValue < rhs.rawValue
	}
}

//MARK: -
///manages communicating with the local docker engine
public final class DockerManager: NSObject {
	// MARK: - Properties
	public fileprivate(set) var containers: [DockerContainer]!
	public var isReady: Bool { return state == .ready }

	let sessionConfig: URLSessionConfiguration
	let session: URLSession
	let api: DockerAPI!
	let dockerLog = OSLog(subsystem: "io.rc2.client", category: "docker")
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
	fileprivate(set) var dataDirectory: URL?
	fileprivate let socketPath = "/var/run/docker.sock"
	///the path to use for the source shared folder for dbserver. overridden when using a remote docker daemon
	fileprivate var remoteLocalSharePath: String?
	/// used for time to start listening to events
	private let startupTime = Int(Date.timeIntervalSinceReferenceDate)
	/// monitors event stream
	fileprivate var eventMonitor: DockerEventMonitor?
	private var state: ManagerState = .unknown

	///has enough time elapsed that we should check to see if there is an update to the docker images
	public var shouldCheckForUpdate: Bool {
		return defaults[.lastImageInfoCheck] + 86400.0 <= Date.timeIntervalSinceReferenceDate
	}

	// MARK: - Initialization

	///Default initializer. After creation, initializeConnection or isDockerRunning must be called
	/// - parameter hostUrl: The base url of the docker daemon (i.e. http://localhost:2375/) to connect to. nil means use /var/run/docker.sock. Also checks for the environment variable "DockerHostUrl" if not specified. If DockerHostUrl is specified, also should define DockerHostSharePath as the path to map to /rc2 in the dbserver container
	/// - parameter baseInfoUrl: the base url where imageInfo.json can be found. Defaults to www.rc2.io.
	/// - parameter userDefaults: defaults to standard user defaults. Allows for dependency injection.
	/// - parameter sessionConfiguration: url configuration to use, defaults to the standard default configuration
	public init(hostUrl host: String? = nil, baseInfoUrl infoUrl: String? = nil, userDefaults: UserDefaults = .standard, sessionConfiguration: URLSessionConfiguration = .default)
	{
		if let hostUrl = host {
			//break down into components
			guard let comps = URLComponents(string: hostUrl) else { fatalError("invalid host string") }
			baseUrl = comps.url!
		} else {
			baseUrl = URL(string: "unix://")
		}
		self.baseInfoUrl = infoUrl == nil ? "https://www.rc2.io/" : infoUrl!
		defaults = userDefaults
		sessionConfig = sessionConfiguration
		sessionConfig.protocolClasses = [DockerUrlProtocol.self] as [AnyClass] + sessionConfig.protocolClasses!
		sessionConfig.requestCachePolicy = .reloadIgnoringLocalCacheData
		session = URLSession(configuration: sessionConfig)
		api = DockerAPIImplementation(baseUrl: baseUrl, sessionConfig: sessionConfig, log: dockerLog)
		//read image info if it is there
		imageInfo = RequiredImageInfo(from: defaults[.cachedImageInfo])
		super.init()
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
		let path: String = Bundle(for: type(of: self)).path(forResource: "dockerInfo", ofType: "json")!
		let jsonStr = String(data: URL(fileURLWithPath: path).contents()!, encoding: .utf8)!
		guard let containerJson = try? JSON(jsonString: jsonStr) else { fatalError() }
		containers = DockerContainer.fromCreateInfoJson(json: containerJson)
		assert(containers.count == ContainerType.all.count)
		self.eventMonitor = DockerEventMonitor(baseUrl: self.baseUrl, delegate: self, sessionConfig: self.sessionConfig)
	}

	deinit {
		session.invalidateAndCancel()
	}

	//MARK: - standard operating procedure

	/// loads version info from docker daemon and then checks for updates to image info from baseInfoUrl
	///
	/// - parameter refresh: if true, discards any cached info about version and required image info
	///
	/// - returns: a signal producer whose value is true if pullImage is necessary
	public func initialize(refresh: Bool = false) -> SignalProducer<Bool, DockerError> {
		if refresh {
			state = .unknown
			versionInfo = nil
		}
		guard state < .initialized && versionInfo == nil else {
			return SignalProducer<Bool, DockerError>(value: true)
		}
		let producer = self.api.loadVersion()
			.flatMap(.concat, transform: verifyValidVersion)
			.map { v in self.versionInfo = v; self.state = .initialized }
			.flatMap(.concat, transform: validateNetwork)
			.flatMap(.concat, transform: validateVolumes)
			.flatMap(.concat, transform: api.loadImages)
			.map { images in self.installedImages = images; return refresh }
			.flatMap(.concat, transform: checkForImageUpdate)
			.map { _ in self.pullIsNecessary() }
		return producer
	}

	/// pulls any images needed from docker hub
	///
	/// - returns: the values are repeated progress handlers
	public func pullImages() -> SignalProducer<PullProgress, DockerError> {
		precondition(imageInfo != nil)
		precondition(imageInfo!.dbserver.size > 0)
		let fullSize = imageInfo!.reduce(0) { val, info in val + info.size }
		pullProgress = PullProgress(name: "all", size: fullSize)
		let producers = imageInfo!.map { img -> SignalProducer<PullProgress, DockerError> in
			print("got pull for \(img.fullName)")
			return self.pullSingleImage(pull: DockerPullOperation(baseUrl: self.baseUrl, imageName: img.fullName, estimatedSize: img.size, config: sessionConfig))
		}
		return SignalProducer.merge(producers)
	}

	/// Ensures docker has the correct containers available and containers property is in sync with docker
	///
	/// - precondition: initialize() must have been called
	///
	/// - returns: a signal producer with no values
	public func prepareContainers() -> SignalProducer<(), DockerError> {
		return self.api.refreshContainers()
			.flatMap(.concat) { containers in return self.mergeContainers(containers) }
			.flatMap(.concat) { containers in return self.createUnavailable(containers: containers) }
			.map { _ in return () }
	}

	// MARK: - possibly public for update management

	/// contacts the baseInfo server to update the image requirements (might be cached)
	///
	/// - parameter forceRefresh: true if any cached information should be discarded
	///
	/// - precondition: initialize() was called
	/// - remark: called as part of initialize() process. Should only call to force an image update check
	///
	/// - returns: a signal producer whose value is always true
	public func checkForImageUpdate(forceRefresh: Bool = false) -> SignalProducer<Bool, DockerError>
	{
		precondition(state >= .initialized)
		//short circuit if we don't need to chedk and have valid data
		guard imageInfo == nil || shouldCheckForUpdate || forceRefresh else {
			os_log("using cached docker info", log:dockerLog, type:.info)
			return SignalProducer<Bool, DockerError>(value: true)
		}
		return api.fetchJson(url: URL(string:"\(baseInfoUrl)imageInfo.json")!).map { json in
			self.imageInfo = RequiredImageInfo(from: json)
			self.defaults[.cachedImageInfo] = json
			self.defaults[.lastImageInfoCheck] = Date.timeIntervalSinceReferenceDate
			return true
		}
	}

	/// compares installedImages with imageInfo to see if a pull is necessary
	///
	/// - remark: initialize() returns the same information
	///
	/// - returns: true if there are newer images we need to pull and pullImages() should be called
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

	// MARK: - container operations

	/// Performs an operation on a container
	///
	/// - parameter operation: the operation to perform
	/// - parameter container: the container to perform the operation on
	///
	/// - returns: a signal producer with no values, just completed or error
	public func perform(operation: DockerContainerOperation, on container: DockerContainer) -> SignalProducer<(), DockerError> {
		return api.perform(operation: operation, container: container)
	}

	/// performs operation on all containers
	///
	/// - parameter operation: the operation to perform
	///
	/// - returns: a signal producer with no value
	public func perform(operation: DockerContainerOperation, on inContainers: [DockerContainer]? = nil) -> SignalProducer<(), DockerError>
	{
		var selectedContainers = containers!
		if inContainers != nil {
			selectedContainers = inContainers!
		}
		return api.perform(operation: operation, containers: selectedContainers)
	}
}

// MARK: - Event Monitor Delegate
extension DockerManager: DockerEventMonitorDelegate {
	/// handles an event from the event monitor
	// note that the only events that external observers should care about (as currently implemented) are related to specific containers, which will update their observable state property. Probably need a way to inform application if some serious problem ocurred
	func handleEvent(_ event: DockerEvent) {
		os_log("got event: %{public}s", log:dockerLog, type:.info, event.description)
		//only care if it is one of our containers
		guard let from = try? event.json.getString(at:"from"),
			let ctype = ContainerType.from(imageName:from),
			let container = containers[ctype] else { return }
		switch event.eventType {
			case .die:
				os_log("warning: container died: %{public}s", log:dockerLog, from)
				if let exitStatusStr = try? event.json.getString(at: "exitCode"),
					let exitStatus = Int(exitStatusStr), exitStatus != 0
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
	/// Validates the version parameter meets requirements.
	///
	/// - parameter version: the version information to check
	///
	/// - returns: a signal producer whose value is the valid version info
	func verifyValidVersion(version: DockerVersion) -> SignalProducer<DockerVersion, DockerError> {
		return SignalProducer<DockerVersion, DockerError>() { observer, _ in
			//force cast because only should be called if versionInfo was set
			if version.apiVersion >= self.requiredApiVersion {
				self.versionInfo = version
				observer.send(value: version)
				observer.sendCompleted()
			} else {
				observer.send(error: .unsupportedDockerVersion)
			}
		}
	}

	fileprivate func validateNetwork() -> SignalProducer<(), DockerError> {
		let nname = "rc2server"
		return api.networkExists(name: nname)
			.map { exists in return (nname, exists, self.api.create(network:)) }
			.flatMap(.concat, transform: optionallyCreateObject)
	}

	fileprivate func validateVolumes() -> SignalProducer<(), DockerError> {
		let nname = "rc2_dbdata"
		return api.volumeExists(name: nname)
			.map { exists in return (nname, exists, self.api.create(volume:)) }
			.flatMap(.concat, transform: optionallyCreateObject)
	}

	typealias CreateFunction = (String) -> SignalProducer<(), DockerError>

	fileprivate func optionallyCreateObject(name: String, exists: Bool, handler: CreateFunction) -> SignalProducer<(), DockerError>
	{
		guard !exists else {
			return SignalProducer<(), DockerError>(value: ())
		}
		return handler(name)
	}

	/// Creates any containers that don't exist
	///
	/// - parameter containers: the containers to create if necessary
	///
	/// - returns: the containers unchanged
	fileprivate func createUnavailable(containers: [DockerContainer]) -> SignalProducer<[DockerContainer], DockerError>
	{
		let producers = containers.map { self.api.create(container: $0) }
		return SignalProducer.merge(producers).collect()
	}

	/// Updates the containers property to match the information in the containers parameter
	///
	/// - parameter containers: containers array from docker
	///
	/// - returns: a signal producer whose value is the merged containers
	fileprivate func mergeContainers(_ containers: [DockerContainer]) -> SignalProducer<[DockerContainer], DockerError>
	{
		return SignalProducer<[DockerContainer], DockerError> { observer, _ in
//			precondition(self.containers.count == containers.count)
			self.containers.forEach { aContainer in
				if let c2 = containers[aContainer.type] {
					aContainer.update(from: c2)
				}
			}
			observer.send(value: self.containers)
			observer.sendCompleted()
		}
	}

	//for now maps promise/future pull operation to a signal producer
	func pullSingleImage(pull: DockerPullOperation) -> SignalProducer<PullProgress, DockerError>
	{
		pullProgress?.extracting = false
		let alreadyDownloaded = pullProgress!.currentSize
		return SignalProducer<PullProgress, DockerError> { (observer, disposable) in
			let future = pull.startPull { pp in
				self.pullProgress?.currentSize = pp.currentSize + alreadyDownloaded
				self.pullProgress?.extracting = pp.extracting
				observer.send(value: self.pullProgress!)
			}
			future.onSuccess { _ in
				observer.sendCompleted()
			}.onFailure { err in
				observer.send(error: .cocoaError(err))
			}
		}
	}

	///creates AppSupport/io.rc2.xxx/v1/dbdata
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
		} catch let err {
			os_log("error setting up data diretory: %{public}s", log:dockerLog, err as NSError)
		}
	}
}
