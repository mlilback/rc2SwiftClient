//
//  DockerManager.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

// TODO: backup database to dataDirectory

import Foundation
import SwiftyJSON
import BrightFutures
import ReactiveSwift
import Result
import ServiceManagement
import os
import SwiftyUserDefaults

// MARK: Keys for UserDefaults
extension DefaultsKeys {
	static let lastImageInfoCheck = DefaultsKey<Double>("lastImageInfoCheck")
	static let dockerImageVersion = DefaultsKey<Int>("dockerImageVersion")
	static let cachedImageInfo = DefaultsKey<JSON?>("cachedImageInfo")
}

//MARK: -
///manages communicating with the local docker engine
open class DockerManager: NSObject {
	// MARK: - Properties
	public let sessionConfig: URLSessionConfiguration
	public let session: URLSession
	public fileprivate(set) var containers: [DockerContainer]!

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
	fileprivate var initialzed = false
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

	// MARK: - Initialization

	///Default initializer. After creation, initializeConnection or isDockerRunning must be called
	/// - parameter hostUrl: The base url of the docker daemon (i.e. http://localhost:2375/) to connect to. nil means use /var/run/docker.sock. Also checks for the environment variable "DockerHostUrl" if not specified. If DockerHostUrl is specified, also should define DockerHostSharePath as the path to map to /rc2 in the dbserver container
	/// - parameter baseInfoUrl: the base url where imageInfo.json can be found. Defaults to www.rc2.io.
	/// - parameter userDefaults: defaults to standard user defaults. Allows for dependency injection.
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
		imageInfo = RequiredImageInfo(json: defaults[.cachedImageInfo])
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
		let containerInfo = JSON(data: URL(fileURLWithPath: path).contents()!)
		assert(containerInfo.dictionary?.count == ContainerType.all.count)
		containers = containerInfo.dictionaryValue.map { key, value in
			DockerContainer(type: ContainerType.from(containerName: key)!)
		}
	}

	///connects to the docker daemon and confirms it is running and meets requirements.
	/// calls initializeConnection()
	/// - returns: Closure called with true if able to connect to docker daemon.
	public func isDockerRunning() -> SignalProducer<Bool, DockerError>  {
		guard initialzed else { return initializeConnection().map { return true } }
		return SignalProducer<Bool, DockerError>(result: Result<Bool, DockerError>(value: true))
	}

	/// Loads basic version information from the docker daemon. Also loads list of docker images that are installed and gets info for existing containers.
	/// Must be called before being using any func except isDockerRunning().
	/// - returns: future. the result will be false if there was an error parsing information from docker.
	public func initializeConnection() -> SignalProducer<(), DockerError> {
		self.initialzed = true
		return loadVersion()
			.flatMap(.concat) { _ in return self.api.loadImages() }
			.flatMap(.concat) { _ in return self.api.refreshContainers() }
			.flatMap(.concat) { containers in return self.mergeContainers(containers) }
			.flatMap(.concat) { containers in return self.createUnavailable(containers: containers) }
			.map { _ in return () }
	}

	// MARK: - Image Manipulation

	/// Checks to see if it is necessary to check for an imageInfo update, and if so, perform that check.
	/// - returns: a future whose success will be true if a pull is required
	public func checkForImageUpdate() -> SignalProducer<Bool, DockerError> {
		precondition(initialzed)
		//short circuit if we don't need to chedk and have valid data
		guard imageInfo == nil || shouldCheckForUpdate else {
			os_log("using cached docker info", log:dockerLog, type:.info)
			return SignalProducer<Bool, DockerError>(value: true)
		}
		return api.fetchJson(url: URL(string:"\(baseInfoUrl)imageInfo.json")!).map { json in
			self.imageInfo = RequiredImageInfo(json: json)
			self.defaults[.cachedImageInfo] = json
			self.defaults[.lastImageInfoCheck] = Date.timeIntervalSinceReferenceDate
			return true
		}
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
	public func pullImages(handler: PullProgressHandler? = nil) -> SignalProducer<PullProgress, DockerError> {
		precondition(imageInfo != nil)
		precondition(imageInfo!.dbserver.size > 0)
		let fullSize = imageInfo!.reduce(0) { val, info in val + info.size }
		pullProgress = PullProgress(name: "all", size: fullSize)
		let producers = imageInfo!.map { self.pullSingleImage(pull: DockerPullOperation(baseUrl: self.baseUrl, imageName: $0.name, estimatedSize: $0.size)) }
		return SignalProducer.merge(producers)
	}
}

// MARK: - Event Monitor Delegate
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
	fileprivate func loadVersion() -> SignalProducer<DockerVersion, DockerError> {
		//if we've already loaded the version info, don't do so again
		guard versionInfo == nil else {
			return SignalProducer<DockerVersion, DockerError>(value: versionInfo!)
		}
		return self.api.loadVersion()
	}

	fileprivate func createUnavailable(containers: [DockerContainer]) -> SignalProducer<[DockerContainer], DockerError>
	{
		let producers = containers.map { self.api.create(container: $0) }
		return SignalProducer.merge(producers).collect()
	}

	fileprivate func mergeContainers(_ containers: [DockerContainer]) -> SignalProducer<[DockerContainer], DockerError>
	{
		return SignalProducer<[DockerContainer], DockerError> { observer, _ in
			precondition(self.containers.count == containers.count)
			self.containers.forEach { aContainer in
				if let c2 = containers[aContainer.type] {
					aContainer.update(from: c2)
				}
			}
			observer.send(value: containers)
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
