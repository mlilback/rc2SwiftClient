//
//  DockerAPIImplementation.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import ReactiveSwift
import Freddy
import Result
import os

// swiftlint:disable file_length type_body_length

/// Default implementation of DockerAPI protocol
public final class DockerAPIImplementation: DockerAPI {
	/// used to hold log data if there wasn't enough for the next chunk
	fileprivate struct LeftoverLogData {
		let data: Data
		let type: UInt8
		let size: Int
	}

	// MARK: - properties
	public let baseUrl: URL
	fileprivate let sessionConfig: URLSessionConfiguration
	fileprivate var session: URLSession
	fileprivate let fileManager: FileManager
	public let scheduler: QueueScheduler
	
	// MARK: - init

	/// Instantiates object to make calls to docker daemon
	///
	/// - parameter baseUrl:       The base URL of the docker socket (e.g. "http://..." or "unix://...")
	/// - parameter sessionConfig: configuration to use for httpsession, defaults to .default
	///
	/// - returns: an instance of this class
	public init(baseUrl: URL = URL(string: "unix://")!, sessionConfig: URLSessionConfiguration = URLSessionConfiguration.default, fileManager: FileManager = FileManager.default)
	{
		precondition(baseUrl.absoluteString.hasPrefix("unix:") || !baseUrl.absoluteString.hasSuffix("/"))
		self.scheduler = QueueScheduler(qos: .default, name: "rc2.dockerAPI")
		self.baseUrl = baseUrl
		self.sessionConfig = sessionConfig
		if sessionConfig.protocolClasses?.filter({ $0 == DockerUrlProtocol.self }).count == 0 {
			sessionConfig.protocolClasses = [DockerUrlProtocol.self] as [AnyClass] + sessionConfig.protocolClasses!
		}
		sessionConfig.requestCachePolicy = .reloadIgnoringLocalCacheData
		session = URLSession(configuration: sessionConfig)
		self.fileManager = fileManager
	}

	// MARK: - general

	// documentation in DockerAPI protocol
	public func loadVersion() -> SignalProducer<DockerVersion, DockerError>
	{
		let req = URLRequest(url: baseUrl.appendingPathComponent("/version"))
		os_log("dm.loadVersion called to %{public}@", log: .docker, type: .debug, req.debugDescription)
		return makeRequest(request: req)
			.optionalLog("loadVersion")
			.flatMap(.concat, transform: dataToJson)
			.flatMap(.concat, transform: parseVersionInfo)
			.observe(on: scheduler)
	}

	// documentation in DockerAPI protocol
	public func fetchJson(url: URL) -> SignalProducer<JSON, DockerError> {
		return self.makeRequest(request: URLRequest(url: url))
			.optionalLog("fetchJson \(url.lastPathComponent)")
			.flatMap(.concat, transform: self.dataToJson)
	}

	// documentation in DockerAPI protocol
	public func fetchLog(container: DockerContainer) -> SignalProducer<String, DockerError>
	{
		let url = baseUrl.appendingPathComponent("containers/\(container.name)/logs")
		var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
		components.queryItems?.append(URLQueryItem(name: "stderr", value: "1"))
		components.queryItems?.append(URLQueryItem(name: "stdout", value: "1"))
		let req = URLRequest(url: components.url!)
		return makeRequest(request: req)
			.optionalLog("\(container.name) logs")
			.map { String(data: $0, encoding: .utf8)! }
	}
	
	// documentation in DockerAPI protocol
	public func streamLog(container: DockerContainer, dataHandler: @escaping LogEntryCallback)
	{
//		let myConfig = sessionConfig
//		myConfig.timeoutIntervalForRequest = TimeInterval(60 * 60 * 24) //wait a day
//		let delegate = ChunkedResponseProxy(handler: dataHandler)
//		let mySession = URLSession(configuration: myConfig, delegate: delegate, delegateQueue:nil)
//		var components = URLComponents(string: "\(DockerUrlProtocol.streamScheme)://containers/\(container.name)/logs")!
//		components.scheme = DockerUrlProtocol.streamScheme
//		components.path = "containers/\(container.name)/logs"
//		components.queryItems?.append(URLQueryItem(name: "stderr", value: "1"))
//		components.queryItems?.append(URLQueryItem(name: "stdout", value: "1"))
//		components.queryItems?.append(URLQueryItem(name: "follow", value: "1"))
		var request = URLRequest(url: URL(string: "dockerstream:/v1.24/containers/\(container.name)/logs?stderr=1&stdout=1&follow=1&timestamps=1")!)
//		var request = URLRequest(url: components.url!)
		request.isHijackedResponse = true
		var leftover: LeftoverLogData?
		let connection = LocalDockerConnectionImpl<HijackedResponseHandler>(request: request, hijack: true) { (message) in
			switch message {
			case .data(let data):
				leftover = self.parseDockerChunk(data: data, leftover: leftover, callback: dataHandler)
			default:
				print("got message")
			}
		}
		do {
			try connection.openConnection()
		} catch {
			//TODO: better error handling
			dataHandler(nil, true)
			return
		}
		connection.writeRequest()
//		let task = mySession.dataTask(with: request as URLRequest)
//		task.resume()
	}
	
	// documentation in DockerAPI protocol
	public func upload(url source: URL, path: String, filename: String, containerName: String) -> SignalProducer<(), DockerError>
	{
		return tarballFile(source: source, filename: filename)
			.flatMap(.concat, transform: {
				self.tarredUpload(file: $0, path: path, containerName: containerName, removeFile: true)
			})
	}
	
	// MARK: - image operations

	// documentation in DockerAPI protocol
	public func loadImages() -> SignalProducer<[DockerImage], DockerError>
	{
		let req = URLRequest(url: baseUrl.appendingPathComponent("/images/json"))
		return makeRequest(request: req)
			.optionalLog("loadImages")
			.flatMap(.concat, transform: dataToJson)
			.flatMap(.concat, transform: parseImages)
			.observe(on: scheduler)
	}

	// MARK: - volume operations

	public func volumeExists(name: String) -> SignalProducer<Bool, DockerError>
	{
		// swiftlint:disable:next force_try // we created from static string, serious programmer error if fails
		let filtersJson = try! JSONSerialization.data(withJSONObject: ["name": [name]], options: [])
		let filtersStr = String(data:filtersJson, encoding:.utf8)!
		var urlcomponents = URLComponents(url: self.baseUrl.appendingPathComponent("/volumes"), resolvingAgainstBaseURL: true)!
		urlcomponents.queryItems = [URLQueryItem(name:"all", value:"1"), URLQueryItem(name:"filters", value:filtersStr)]
		let req = URLRequest(url: urlcomponents.url!)

		return makeRequest(request: req)
			.optionalLog("vol \(name) exists", events: LoggingEvent.SignalProducer.allEvents)
			.flatMap(.concat, transform: { (data) -> SignalProducer<Bool, DockerError> in
				return SignalProducer<Bool, DockerError> { observer, _ in
					self.jsonCheckHandler(observer: observer, data: data) { json in
						guard let filteredVolumes = try? json.getArray(at: "Volumes") else { return false }
						return try filteredVolumes.filter( { aVolume in
							return try aVolume.getString(at: "Name") == name
						}).count == 1
					}
				}
			}).observe(on: scheduler)
	}

	/// documentation in DockerAPI protocol
	public func create(volume: String) -> SignalProducer<(), DockerError>
	{
		var props = [String: Any]()
		props["Name"] = volume
		props["Labels"] = ["rc2.live": ""]
		// swiftlint:disable:next force_try
		let jsonData = try! JSONSerialization.data(withJSONObject: props, options: [])
		var request = URLRequest(url: baseUrl.appendingPathComponent("/volumes/create"))
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		return SignalProducer<(), DockerError> { observer, _ in
			let task = self.session.uploadTask(with: request, from: jsonData) { (data, response, error) in
				self.statusCodeResponseHandler(observer: observer, data: data, response: response, error: error) {}
			}
			task.resume()
		}.optionalLog("create vol \(volume)").observe(on: scheduler)
	}

	// MARK: - container operations

	// documentation in DockerAPI protocol
	public func refreshContainers() -> SignalProducer<[DockerContainer], DockerError>
	{
		return self.makeRequest(request: self.containersRequest())
			.optionalLog("refresh containers")
			.flatMap(.concat, transform: dataToJson)
			.flatMap(.concat, transform: parseContainers)
			.observe(on: scheduler)
	}

	// documentation in DockerAPI protocol
	public func perform(operation: DockerContainerOperation, containers: [DockerContainer]) -> SignalProducer<(), DockerError>
	{
		let producers = containers
			.map({ self.perform(operation: operation, container: $0) })
		let producer = SignalProducer< SignalProducer<(), DockerError>, DockerError >(producers)
		return producer
			.optionalLog("perform multiple \(operation.rawValue)")
			.flatten(.merge)
			.collect()
			.map { _ in return () }
	}

	// documentation in DockerAPI protocol
	public func perform(operation: DockerContainerOperation, container: DockerContainer) -> SignalProducer<(), DockerError>
	{
		os_log("performing %{public}@ on %{public}@", log: .docker, type: .debug, operation.rawValue as String, container.name)
		if operation == .start && container.state.value == .running {
			//already running, no need to start
			return SignalProducer<(), DockerError>(result: Result<(), DockerError>(value: ()))
		}
		let url = baseUrl.appendingPathComponent("/containers/\(container.name)/\(operation.rawValue)")
		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		return SignalProducer<(), DockerError> { observer, _ in
			self.session.dataTask(with: request) { (data, response, error) in
				self.statusCodeResponseHandler(observer: observer, data: data, response: response, error: error) {
					observer.send(value: ())
				}
			}.resume()
		}.optionalLog("perform \(operation.rawValue) on \(container.name)").observe(on: scheduler)
	}

	// documentation in DockerAPI protocol
	public func create(container: DockerContainer) -> SignalProducer<DockerContainer, DockerError>
	{
		return SignalProducer<DockerContainer, DockerError> { observer, _ in
			os_log("creating container %{public}@", log: .docker, type: .debug, container.name)
			guard container.state.value == .notAvailable else {
				observer.send(value: container)
				observer.sendCompleted()
				return
			}
			guard let jsonData = container.createInfo else {
				observer.send(error: DockerError.invalidJson(nil))
				return
			}
			//swiftlint:disable:next force_try
//			try! jsonData.write(to: URL(fileURLWithPath: "/tmp/json.\(container.type.rawValue).json"))
			var comps = URLComponents(url: URL(string:"/containers/create", relativeTo:self.baseUrl)!, resolvingAgainstBaseURL: true)!
			comps.queryItems = [URLQueryItem(name:"name", value:container.name)]
			var request = URLRequest(url: comps.url!)
			request.httpMethod = "POST"
			request.setValue("application/json", forHTTPHeaderField: "Content-Type")
			let task = self.session.uploadTask(with: request, from: jsonData) { (data, response, error) in
				self.statusCodeResponseHandler(observer: observer, data: data, response: response, error: error) {
					observer.send(value: container)
				}
			}
			task.resume()
		}.optionalLog("create container \(container.name)")
	}

	/// documentation in DockerAPI protocol
	public func remove(container: DockerContainer) -> SignalProducer<(), DockerError>
	{
		let url = baseUrl.appendingPathComponent("/containers/\(container.name)")
		var request = URLRequest(url: url)
		request.httpMethod = "DELETE"
		return SignalProducer<Void, DockerError> { observer, _ in
			os_log("removing %{public}@", log: .docker, type: .info, container.name)
			self.session.dataTask(with: request) { (data, response, error) in
				self.statusCodeResponseHandler(observer: observer, data: data, response: response, error: error) {}
			}.resume()
		}.optionalLog("remove container \(container.name)").observe(on: scheduler)
	}

	/// documentation in DockerAPI protocol
	public func execute(command: [String], container: DockerContainer) -> SignalProducer<(Int, Data), DockerError>
	{
		return prepExecTask(command: command, container: container)
			.flatMap(.concat, transform: { (taskId) in
				return self.runExecTask(taskId: taskId)
			})
			.flatMap(.concat, transform: { (arg) in
				return self.checkExecSuccess(taskId: arg.0, data: arg.1)
			})
	}

	/// documentation in DockerAPI protocol
	public func executeSync(command: [String], container: DockerContainer) -> SignalProducer<Data, DockerError>
	{
		precondition(command.count > 0)
		return prepExecTask(command: command, container: container)
			.flatMap(.concat, transform: dataForExecTask)
	}
	
	// MARK: - network operations

	/// documentation in DockerAPI protocol
	public func create(network: String) -> SignalProducer<(), DockerError>
	{
		var props = [String: Any]()
		props["Internal"] = false
		props["Driver"] = "bridge"
		props["Name"] = network
		// swiftlint:disable:next force_try
		let jsonData = try! JSONSerialization.data(withJSONObject: props, options: [])
		var request = URLRequest(url: baseUrl.appendingPathComponent("/networks/create"))
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		return SignalProducer<(), DockerError> { observer, _ in
			let task = self.session.uploadTask(with: request, from: jsonData) { (data, response, error) in
				self.statusCodeResponseHandler(observer: observer, data: data, response: response, error: error) {}
			}
			task.resume()
		}.optionalLog("create net \(network)").observe(on: scheduler)
	}

	/// documentation in DockerAPI protocol
	public func networkExists(name: String) -> SignalProducer<Bool, DockerError>
	{
		let req = URLRequest(url: baseUrl.appendingPathComponent("/networks"))
		return makeRequest(request: req)
			.flatMap(.concat, transform: { (data) -> SignalProducer<Bool, DockerError> in
				return SignalProducer<Bool, DockerError> { observer, _ in
					self.jsonCheckHandler(observer: observer, data: data) { json in
						guard let networks = try? json.getArray() else { return false }
						//nets is now json cast safely to [JSON]
						let matches = networks.flatMap { network -> JSON? in
							guard let itemName = try? network.getString(at: "Name") else { return nil }
							if itemName == name { return network }
							return nil
						}
						return matches.count == 1
					}
				}
			}).optionalLog("net \(name) exists").observe(on: scheduler)
	}
}

// MARK: private methods
extension DockerAPIImplementation {
	/// convience method to parse Data into JSON
	///
	/// - parameter data: data to parse
	///
	/// - returns: parsed JSON
	fileprivate func dataToJson(data: Data) -> SignalProducer<JSON, DockerError>
	{
		return SignalProducer<JSON, DockerError> { observer, _ in
			do {
				let json = try JSON(data: data)
				observer.send(value: json)
				observer.sendCompleted()
			} catch {
				observer.send(error: DockerError.invalidJson(error))
			}
		}
	}

	/// parses JSON from docker daemon into version information
	///
	/// - parameter json: json object with version information
	///
	/// - returns: the version information
	fileprivate func parseVersionInfo(json: JSON) -> SignalProducer<DockerVersion, DockerError>
	{
		return SignalProducer<DockerVersion, DockerError> { observer, _ in
			do {
				os_log("parsing version info: %{public}@", log: .docker, type: .debug, try json.serializeString())
				let regex = try NSRegularExpression(pattern: "(\\d+)\\.(\\d+)\\.(\\d+)", options: [])
				let verStr = try json.getString(at: "Version")
				guard let match = regex.firstMatch(in: verStr, options: [], range: verStr.fullNSRange),
					let primaryVersion = Int((verStr as NSString).substring(with: match.range(at:1))),
					let secondaryVersion = Int((verStr as NSString).substring(with: match.range(at:2))),
					let fixVersion = Int((verStr as NSString).substring(with: match.range(at:3))),
					let apiStr = try? json.getString(at: "ApiVersion"),
					let apiVersion = Double(apiStr) else
				{
					observer.send(error: DockerError.invalidJson(nil)) //FIXME: better error reporting
					return
				}
				observer.send(value: DockerVersion(major: primaryVersion, minor: secondaryVersion, fix: fixVersion, apiVersion: apiVersion))
				observer.sendCompleted()
			} catch let err as NSError {
				observer.send(error: DockerError.cocoaError(err))
			}
		}
	}

	/// - returns: a URLRequest to fetch list of containers
	fileprivate func containersRequest() -> URLRequest
	{
		// swiftlint:disable:next force_try
		let filtersJson = try! JSONSerialization.data(withJSONObject: ["label": ["rc2.live"]], options: [])
		let filtersStr = String(data:filtersJson, encoding:.utf8)!
		var urlcomponents = URLComponents(url: self.baseUrl.appendingPathComponent("/containers/json"), resolvingAgainstBaseURL: true)!
		urlcomponents.queryItems = [URLQueryItem(name:"all", value:"1"), URLQueryItem(name:"filters", value:filtersStr)]
		return URLRequest(url: urlcomponents.url!)
	}

	/// parse a chunk of log lines (i.e. blocks)
	///
	/// - Parameters:
	///   - data: chunk of log entries with 8 byte header
	///   - leftover: any partial chunk data returned from the last call
	///   - callback: called with each string entry from the log
	fileprivate func parseDockerChunk(data: Data, leftover: LeftoverLogData?, callback: @escaping LogEntryCallback) -> LeftoverLogData?
	{
		let headerSize: Int = 8
		var currentOffset: Int = 0
		var data = Data(data) //mutatable copy
		// add new data to old data
		repeat {
			let (type, size): (UInt8, Int)
			if let leftover = leftover {
				(type, size) = (leftover.type, leftover.size)
				data = leftover.data + data
			} else {
				// cast first 8 bytes to array of 2 Int32s. Convert the second to big endian to get size of message
				(type, size) = data.subdata(in: currentOffset..<currentOffset + headerSize).withUnsafeBytes
				{ (ptr: UnsafePointer<UInt8>) -> (UInt8, Int) in
					return (ptr[0], ptr.withMemoryRebound(to: Int32.self, capacity: 2)
					{ (intPtr: UnsafePointer<Int32>) -> Int in
						return Int(Int32(bigEndian: intPtr[1]))
					})
				}
			}
			// type must be stdout or stderr
			guard type == 1 || type == 2 else {
				// FIXME: need to have way to pass error back to caller. until then, crash
				fatalError("invalid hijacked stream type")
			}
			currentOffset += headerSize
			let nextOffset = currentOffset + size
			// if all the data required is not available, break out of loop
			guard nextOffset <= data.count else {
				return LeftoverLogData(data: data.subdata(in: currentOffset..<data.count), type: type, size: size)
			}
			// pass the data as a string to handler
			let currentChunk = data.subdata(in: currentOffset..<nextOffset)
			callback(String(data: currentChunk, encoding: .utf8), type == 2)
			// mark that data as used
			currentOffset += size
		} while data.count > currentOffset
		return nil
	}

	/// handles sending completed or error for a docker response based on http status code
	func statusCodeResponseHandler<T>(observer: Observer<T, DockerError>, data: Data?, response: URLResponse?, error: Error?, valueHandler:(() -> Void))
	{
		guard let rsp = response as? HTTPURLResponse, error == nil else {
			os_log("api remote error: %{public}@", log: .docker, type: .default, error! as NSError)
			if let dockerError = error as? DockerError {
				observer.send(error: dockerError)
			} else {
				observer.send(error: DockerError.networkError(error as NSError?))
			}
			return
		}
		os_log("api status: %d", log: .docker, type: .debug, rsp.statusCode)
		switch rsp.statusCode {
		case 201, 204, 304: //spec says 204, but should be 201 for created. we'll handle both
			valueHandler()
			observer.sendCompleted()
		case 404:
			observer.send(error: DockerError.noSuchObject)
		case 409:
			fallthrough
		default:
			observer.send(error: DockerError.httpError(statusCode: rsp.statusCode, description: nil, mimeType: nil))
		}
	}

	/// takes the data from a request and allows easy filtering of it
	///
	/// - parameter observer: the observer to send signals on
	/// - parameter data:     the data from a GET request
	/// - parameter filter:   a closure that determines if the json meets requirements
	func jsonCheckHandler(observer: Observer<Bool, DockerError>, data: Data?, filter: ((JSON) throws -> Bool))
	{
		guard let data = data else {
			observer.send(error: DockerError.invalidArgument("no data"))
			return
		}
		var json: JSON?
		var result: Bool = false
		do {
			json = try JSON(data: data)
			result = try filter(json!)
		} catch {
			observer.send(error: DockerError.invalidJson(error))
			return
		}
		observer.send(value: result)
		observer.sendCompleted()
	}

	//must not reference self
	fileprivate func parseContainers(json: JSON) -> SignalProducer<[DockerContainer], DockerError>
	{
		do {
			let containers: [DockerContainer] = try json.decodedArray()
			return SignalProducer<[DockerContainer], DockerError>(value: containers)
		} catch {
			return SignalProducer<[DockerContainer], DockerError>(error: DockerError.invalidJson(error))
		}
	}

	fileprivate func parseImages(json: JSON) -> SignalProducer<[DockerImage], DockerError>
	{
		guard let images = try? json.getArray().flatMap({ (imgJson: JSON) -> DockerImage? in
			guard let img = try? DockerImage(json: imgJson) else { return nil }
			return img
		}) else {
			return SignalProducer<[DockerImage], DockerError>(error: DockerError.invalidJson(nil)) //FIXME: pass nested error
		}
		return SignalProducer<[DockerImage], DockerError> { observer, _ in
			let filteredImages = images.filter({ $0.labels.keys.contains("io.rc2.type") && $0.tags.count > 0 })
			observer.send(value: filteredImages)
			observer.sendCompleted()
		}
	}

	@discardableResult
	/// return a signal producer that will make a request
	///
	/// - Parameter request: the request to make
	/// - Returns: a signal producer that will make the request
	fileprivate func makeRequest(request: URLRequest) -> SignalProducer<Data, DockerError>
	{
		return SignalProducer<Data, DockerError> { observer, _ in
			self.make(request: request, observer: observer)
		}
	}

	/// Make a request passing data or error to the observer
	///
	/// - Parameters:
	///   - request: request to make
	///   - observer: observer to send results or error
	fileprivate func make(request: URLRequest, observer: Signal<Data, DockerError>.Observer)
	{
		self.session.dataTask(with: request, completionHandler: { (data, response, error) in
			guard let rawData = data, error == nil else {
				observer.send(error: DockerError.networkError(error as NSError?))
				return
			}
			if rawData.count == 0 {
				os_log("request returned no data", log: .docker, type: .debug)
			}
			//default to 200 for non-http status codes (such as file urls)
			let statusCode = response?.httpResponse?.statusCode ?? 200
			guard statusCode >= 200 && statusCode < 400 else {
				let rsp = response!.httpResponse!
				os_log("docker request got bad status: %d response = %{public}@", log: .docker, rsp.statusCode, String(data: data!, encoding: .utf8)!)
				observer.send(error: DockerError.generateHttpError(from: rsp, body: data))
				return
			}
			observer.send(value: rawData)
			observer.sendCompleted()
		}).resume()
	}

	/// tar a file
	///
	/// - Parameters:
	///   - source: file to tar
	///   - filename: name to encoded in tar file
	/// - Returns: signal producer to return tarred file URL
	func tarballFile(source: URL, filename: String = "data.sql") -> SignalProducer<URL, DockerError>
	{
		precondition(source.isFileURL && source.fileExists())
		let tarfilename = "data.tar"
		let fm = fileManager //so no ref to self in closure
		return SignalProducer<URL, DockerError> { observer, _ in
			// create a working directory
			let workingDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
			print("working with \(workingDir.path)")
			let tmpFile = workingDir.appendingPathComponent(filename)
			do {
				precondition(!workingDir.directoryExists())
				try fm.createDirectory(at: workingDir, withIntermediateDirectories: true, attributes: nil)
				// try linking file (faster)
				if ((try? fm.linkItem(at: source, to: tmpFile)) != nil) {
					//failed to link, copy it
					try fm.copyItem(at: source, to: tmpFile)
				}
				//tar the file
				let tar = Process()
				tar.currentDirectoryPath = workingDir.path
				tar.arguments = ["cf", tarfilename, filename]
				tar.launchPath = "/usr/bin/tar"
				tar.terminationHandler = { process in
					guard process.terminationStatus == 0 else {
						observer.send(error: DockerError.internalError("failed to tar src file"))
						os_log("tar creation: %d", log: .app, type: .default, process.terminationReason.rawValue)
						return
					}
					observer.send(value: workingDir.appendingPathComponent(tarfilename))
					observer.sendCompleted()
				}
				tar.launch()
			} catch {
				observer.send(error: .cocoaError(error as NSError))
			}
		}
	}
	
	/// uploads a tarred file to the specified container
	///
	/// - Parameters:
	///   - file: file in tar format to upload
	///   - path: path to extract file into
	///   - containerName: container to upload to
	///   - removeFile: true if the file should be deleted on completion. defaults to true.
	/// - Returns: signal producer without a return value
	func tarredUpload(file: URL, path: String, containerName: String, removeFile: Bool = true) -> SignalProducer<(), DockerError>
	{
		os_log("uploading %{public}@", log: .docker, type: .info, file.path)
		var producer = SignalProducer<(), DockerError> { observer, _ in
			// build request
			let url = self.baseUrl.appendingPathComponent("/containers/\(containerName)/archive")
			guard var urlcomp = URLComponents(url: url, resolvingAgainstBaseURL: true) else { fatalError("failed to prepare url") }
			urlcomp.queryItems = [/*URLQueryItem(name: "noOverwriteDirNonDir", value: overwrite ? "true" : "false"), */ URLQueryItem(name: "path", value: path)]
			guard let builtUrl = urlcomp.url else { fatalError("failed to create upload url") }
			var req = URLRequest(url: builtUrl)
			req.httpMethod = "PUT"
			req.setValue("*/*", forHTTPHeaderField: "Accept")
			req.setValue("application/x-tar", forHTTPHeaderField: "Content-Type")
			req.httpBody = try? Data(contentsOf: file)
			// make the request
			var connection: LocalDockerConnection? = nil
			connection = LocalDockerConnectionImpl<SingleDataResponseHandler>(request: req)
			{ [weak connection] (message) in
				switch message {
				case .headers(let headers):
					print("rsp=\(headers.statusCode)")
					break
				case .data(let data):
					print("got data len \(data.count)")
				case .complete:
					observer.sendCompleted()
					connection?.closeConnection()
				case .error(let err):
					observer.send(error: err)
					connection?.closeConnection()
				}
			}
			try? connection?.openConnection()
			connection?.writeRequest()
		}
		if removeFile {
			producer = producer.on(terminated: { try? self.fileManager.removeItem(at: file) })
		}
		return producer
	}
}

// MARK: execute methods
extension DockerAPIImplementation {
	
	/// Prepare an exec task on the docker server
	///
	/// - Parameters:
	///   - command: array of command arguements to execute
	///   - container: container to excute inside of
	/// - Returns: SignalProducer with the unique ID for this execution task
	fileprivate func prepExecTask(command: [String], container: DockerContainer) -> SignalProducer<String, DockerError>
	{
		let encodedCommand: [JSON] = command.map { .string($0) }
		let json: JSON = .dictionary(["AttachStdout": .bool(true), "Cmd": .array(encodedCommand)])
		var request = URLRequest(url: URL(string: "/containers/\(container.name)/exec")!)
		request.httpMethod = "POST"
		request.addValue("application/json", forHTTPHeaderField: "Content-Type")
		do {
			let str = try json.serializeString() + "\n"
			request.httpBody = str.data(using: .utf8)
		} catch {
			return SignalProducer<String, DockerError>(error: DockerError.invalidJson(error))
		}
		return SignalProducer<String, DockerError> { observer, _ in
			var ended = false // have we sent a completed/error event to observer. don't want to send twice
			let connection = LocalDockerConnectionImpl<SingleDataResponseHandler>(request: request) { (message) in
				switch message {
				case .headers(_):
					break
				case .data(let data):
					do {
						let json = try JSON(data: data)
						let str = try json.getString(at: "Id")
						observer.send(value: str)
					} catch {
						observer.send(error: DockerError.networkError(error as NSError?))
						ended = true
					}
				case .complete:
					if !ended {
						observer.sendCompleted()
						ended = true
					}
				case .error(let err):
					if !ended {
						observer.send(error: DockerError.networkError(err as NSError?))
						ended = true
					}
				}
			}
			do {
				try connection.openConnection()
			} catch {
				observer.send(error: DockerError.networkError(error as NSError))
			}
			connection.writeRequest()
		}
	}
	
	fileprivate func runExecTask(taskId: String) -> SignalProducer<(String, Data), DockerError> {
		var request = URLRequest(url: URL(string: "/exec/\(taskId)/start")!)
		request.httpMethod = "POST"
		request.addValue("application/json", forHTTPHeaderField: "Content-Type")
		request.httpBody = "{}".data(using: .utf8)
		return SignalProducer<(String, Data), DockerError> { observer, _ in
			var inData = Data()
			let connection = LocalDockerConnectionImpl<SingleDataResponseHandler>(request: request) { (message) in
				switch message {
				case .headers(_):
					break
				case .data(let data):
					inData.append(data)
				case .complete:
					observer.send(value: (taskId, inData))
					observer.sendCompleted()
				case .error(let err):
					observer.send(error: DockerError.networkError(err as NSError?))
				}
			}
			do {
				try connection.openConnection()
			} catch {
				observer.send(error: DockerError.networkError(error as NSError))
			}
			connection.writeRequest()
		}
	}
	
	fileprivate func dataForExecTask(taskId: String) -> SignalProducer<Data, DockerError> {
		var request = URLRequest(url: URL(string: "/exec/\(taskId)/start")!)
		request.httpMethod = "POST"
		request.addValue("application/json", forHTTPHeaderField: "Content-Type")
		request.addValue("application/vnd.docker.raw-stream", forHTTPHeaderField: "Accept")
		let bodyData = "{}".data(using: .utf8)!
		request.httpBody = bodyData
		return SignalProducer<Data, DockerError> { observer, _ in
			var inData = Data()
			let connection = LocalDockerConnectionImpl<SingleDataResponseHandler>(request: request) { (message) in
				switch message {
				case .headers(_):
					break
				case .data(let data):
					inData.append(data)
				case .complete:
					if inData.count > bodyData.count, Data(inData[0..<bodyData.count]) == bodyData {
						// it is returning our body data echoed at beginning, which never happens via curl or the command line. Strip it.
						inData.removeSubrange(0..<bodyData.count)
					}
					observer.send(value: inData)
					observer.sendCompleted()
				case .error(let err):
					observer.send(error: DockerError.networkError(err as NSError?))
				}
			}
			do {
				try connection.openConnection()
			} catch {
				observer.send(error: DockerError.networkError(error as NSError))
			}
			connection.writeRequest()
		}
	}
	
	fileprivate func checkExecSuccess(taskId: String, data: Data) -> SignalProducer<(Int, Data), DockerError> {
		return SignalProducer<(Int, Data), DockerError> { observer, _ in
			self.singleExecCheck(taskId: taskId, data: data, observer: observer, attempts: 3)
		}
	}
	
	fileprivate func singleExecCheck(taskId: String, data: Data, observer: Signal<(Int, Data), DockerError>.Observer, attempts: Int)
	{
		guard attempts > 0 else {
			observer.send(error: DockerError.execFailed)
			return
		}
		let request = URLRequest(url: URL(string: "/exec/\(taskId)/json")!)
		var ended = false
		let connection = LocalDockerConnectionImpl<SingleDataResponseHandler>(request: request)
		{ (message) in
			switch message {
			case .headers(_):
				break
			case .data(let data):
				do {
					let json = try JSON(data: data)
					let running = try json.getBool(at: "Running")
					guard !running else {
						ended = true
						self.singleExecCheck(taskId: taskId, data: data, observer: observer, attempts: attempts - 1)
						return
					}
					let exitCode = try json.getInt(at: "ExitCode")
					observer.send(value: (exitCode, data))
				} catch {
					observer.send(error: DockerError.networkError(error as NSError?))
				}
			case .complete:
				if !ended { observer.sendCompleted() }
			case .error(let err):
				if !ended { observer.send(error: DockerError.networkError(err as NSError?)) }
			}
		}
		//give half a second for the execute to run
		DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
			do {
				try connection.openConnection()
			} catch {
				observer.send(error: DockerError.networkError(error as NSError))
			}
			connection.writeRequest()
		}
	}
}
