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
import ClientCore

/// Default implementation of DockerAPI protocol
final class DockerAPIImplementation: DockerAPI {
	// MARK: - properties
	public let baseUrl: URL
	fileprivate let sessionConfig: URLSessionConfiguration
	fileprivate var session: URLSession
	public let scheduler: QueueScheduler

	// MARK: - init

	/// Instantiates object to make calls to docker daemon
	///
	/// - parameter baseUrl:       The base URL of the docker socket (e.g. "http://..." or "unix://...")
	/// - parameter sessionConfig: configuration to use for httpsession, defaults to .default
	///
	/// - returns: an instance of this class
	init(baseUrl: URL = URL(string: "unix://")!, sessionConfig: URLSessionConfiguration = URLSessionConfiguration.default)
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
	}

	// MARK: - general

	// documentation in DockerAPI protocol
	public func loadVersion() -> SignalProducer<DockerVersion, Rc2Error>
	{
		let req = URLRequest(url: baseUrl.appendingPathComponent("/version"))
		os_log("dm.loadVersion called to %{public}s", log: .docker, type: .debug, req.debugDescription)
		return makeRequest(request: req)
			.optionalLog("loadVersion")
			.flatMap(.concat, transform: dataToJson)
			.flatMap(.concat, transform: parseVersionInfo)
			.observe(on: scheduler)
	}

	// documentation in DockerAPI protocol
	public func fetchJson(url: URL) -> SignalProducer<JSON, Rc2Error> {
		return self.makeRequest(request: URLRequest(url: url))
			.optionalLog("fetchJson \(url.lastPathComponent)")
			.flatMap(.concat, transform: self.dataToJson)
	}

	// documentation in DockerAPI protocol
	public func fetchLog(container: DockerContainer) -> SignalProducer<String, Rc2Error>
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
	public func streamLog(container: DockerContainer, dataHandler: @escaping (_ string: String?, _ isStdErr: Bool) -> Void)
	{
		let myConfig = sessionConfig
		myConfig.timeoutIntervalForRequest = TimeInterval(60 * 60 * 24) //wait a day
		let delegate = ChunkedResponseProxy(handler: dataHandler)
		let mySession = URLSession(configuration: myConfig, delegate: delegate, delegateQueue:nil)
//		var components = URLComponents(string: "\(DockerUrlProtocol.streamScheme)://containers/\(container.name)/logs")!
//		components.scheme = DockerUrlProtocol.streamScheme
//		components.path = "containers/\(container.name)/logs"
//		components.queryItems?.append(URLQueryItem(name: "stderr", value: "1"))
//		components.queryItems?.append(URLQueryItem(name: "stdout", value: "1"))
//		components.queryItems?.append(URLQueryItem(name: "follow", value: "1"))
		var request = URLRequest(url: URL(string: "dockerstream:/v1.24/containers/\(container.name)/logs?stderr=1&stdout=1&follow=true")!)
//		var request = URLRequest(url: components.url!)
		request.isHijackedResponse = true
		let task = mySession.dataTask(with: request as URLRequest)
		task.resume()
	}
	
	// documentation in DockerAPI protocol
	public func execCommand(command: [String], container: DockerContainer) -> SignalProducer<Data, Rc2Error>
	{
		precondition(command.count > 0)
		//create an exec job
		var req = URLRequest(url: baseUrl.appendingPathComponent("containers/\(container.name)/exec"))
		req.httpMethod = "POST"
		req.setValue("application-json", forHTTPHeaderField: "Content-Type")
		req.setValue("application-json", forHTTPHeaderField: "Accept")
		do {
			let json: JSON = .dictionary(["AttachStdout": .bool(true), "Tty": .bool(false), "Cmd": command.toJSON()])
			let data = try json.serialize()
			req.httpBody = data
		} catch {
			return SignalProducer<Data, Rc2Error>(error: Rc2Error(type: .invalidJson, nested: error))
		}
		return self.makeRequest(request: req)
			.optionalLog("execCommand \(command[0]) on \(container.name)")
			.flatMap(.concat, transform: self.dataToJson)
			.flatMap(.concat) { (json) -> SignalProducer<Data, Rc2Error> in
				//start the exec job
				guard let execId: String = try? json.getString(at: "Id") else {
					return SignalProducer<Data, Rc2Error>(error: Rc2Error(type: .invalidJson))
				}
				var req2 = URLRequest(url: self.baseUrl.appendingPathComponent("exec/\(execId)/start"))
				req2.httpMethod = "POST"
				req2.setValue("application-json", forHTTPHeaderField: "Content-Type")
				req2.setValue("application/vnd.docker.raw-stream", forHTTPHeaderField: "Accept")
				do {
					let json: JSON = .dictionary(["Detach": .bool(false), "Tty": .bool(false)])
					req2.httpBody = try json.serialize()
				} catch {
					return SignalProducer<Data, Rc2Error>(error: Rc2Error(type: .invalidJson, nested: error))
				}
				return self.makeRequest(request: req2)
			}
	}
	
	// MARK: - image operations

	// documentation in DockerAPI protocol
	public func loadImages() -> SignalProducer<[DockerImage], Rc2Error>
	{
		let req = URLRequest(url: baseUrl.appendingPathComponent("/images/json"))
		return makeRequest(request: req)
			.optionalLog("loadImages")
			.flatMap(.concat, transform: dataToJson)
			.flatMap(.concat, transform: parseImages)
			.observe(on: scheduler)
	}

	// MARK: - volume operations

	public func volumeExists(name: String) -> SignalProducer<Bool, Rc2Error>
	{
		// swiftlint:disable:next force_try // we created from static string, serious programmer error if fails
		let filtersJson = try! JSONSerialization.data(withJSONObject: ["name": [name]], options: [])
		let filtersStr = String(data:filtersJson, encoding:.utf8)!
		var urlcomponents = URLComponents(url: self.baseUrl.appendingPathComponent("/volumes"), resolvingAgainstBaseURL: true)!
		urlcomponents.queryItems = [URLQueryItem(name:"all", value:"1"), URLQueryItem(name:"filters", value:filtersStr)]
		let req = URLRequest(url: urlcomponents.url!)

		return makeRequest(request: req)
			.optionalLog("vol \(name) exists", events: LoggingEvent.SignalProducer.allEvents)
			.flatMap(.concat, transform: { (data) -> SignalProducer<Bool, Rc2Error> in
				return SignalProducer<Bool, Rc2Error> { observer, _ in
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
	func create(volume: String) -> SignalProducer<(), Rc2Error>
	{
		var props = [String: Any]()
		props["Name"] = volume
		props["Labels"] = ["rc2.live": ""]
		// swiftlint:disable:next force_try
		let jsonData = try! JSONSerialization.data(withJSONObject: props, options: [])
		var request = URLRequest(url: baseUrl.appendingPathComponent("/volumes/create"))
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		return SignalProducer<(), Rc2Error> { observer, _ in
			let task = self.session.uploadTask(with: request, from: jsonData) { (data, response, error) in
				self.statusCodeResponseHandler(observer: observer, data: data, response: response, error: error) {}
			}
			task.resume()
		}.optionalLog("create vol \(volume)").observe(on: scheduler)
	}

	// MARK: - container operations

	// documentation in DockerAPI protocol
	public func refreshContainers() -> SignalProducer<[DockerContainer], Rc2Error>
	{
		return self.makeRequest(request: self.containersRequest())
			.optionalLog("refresh containers")
			.flatMap(.concat, transform: dataToJson)
			.flatMap(.concat, transform: parseContainers)
			.observe(on: scheduler)
	}

	// documentation in DockerAPI protocol
	public func perform(operation: DockerContainerOperation, containers: [DockerContainer]) -> SignalProducer<(), Rc2Error>
	{
		let producers = containers
			.map({ self.perform(operation: operation, container: $0) })
		let producer = SignalProducer< SignalProducer<(), Rc2Error>, Rc2Error >(producers)
		return producer
			.optionalLog("perform multiple \(operation.rawValue)")
			.flatten(.merge)
			.collect()
			.map { _ in return () }
	}

	// documentation in DockerAPI protocol
	public func perform(operation: DockerContainerOperation, container: DockerContainer) -> SignalProducer<(), Rc2Error>
	{
		os_log("performing %{public}@ on %{public}@", log: .docker, type: .debug, operation.rawValue as String, container.name)
		if operation == .start && container.state.value == .running {
			//already running, no need to start
			return SignalProducer<(), Rc2Error>(result: Result<(), Rc2Error>(value: ()))
		}
		let url = baseUrl.appendingPathComponent("/containers/\(container.name)/\(operation.rawValue)")
		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		return SignalProducer<(), Rc2Error> { observer, _ in
			self.session.dataTask(with: request) { (data, response, error) in
				self.statusCodeResponseHandler(observer: observer, data: data, response: response, error: error) {
					observer.send(value: ())
				}
			}.resume()
		}.optionalLog("perform \(operation.rawValue) on \(container.name)").observe(on: scheduler)
	}

	// documentation in DockerAPI protocol
	func create(container: DockerContainer) -> SignalProducer<DockerContainer, Rc2Error>
	{
		return SignalProducer<DockerContainer, Rc2Error> { observer, _ in
			os_log("creating container %{public}@", log: .docker, type: .debug, container.name)
			guard container.state.value == .notAvailable else {
				observer.send(value: container)
				observer.sendCompleted()
				return
			}
			guard let jsonData = container.createInfo else {
				observer.send(error: Rc2Error(type: .invalidJson))
				return
			}
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
	func remove(container: DockerContainer) -> SignalProducer<(), Rc2Error>
	{
		let url = baseUrl.appendingPathComponent("/containers/\(container.name)")
		var request = URLRequest(url: url)
		request.httpMethod = "DELETE"
		return SignalProducer<Void, Rc2Error> { observer, _ in
			os_log("removing %{public}@", log: .docker, type: .info, container.name)
			self.session.dataTask(with: request) { (data, response, error) in
				self.statusCodeResponseHandler(observer: observer, data: data, response: response, error: error) {}
			}.resume()
		}.optionalLog("remove container \(container.name)").observe(on: scheduler)
	}

	// MARK: - network operations

	/// documentation in DockerAPI protocol
	func create(network: String) -> SignalProducer<(), Rc2Error>
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
		return SignalProducer<(), Rc2Error> { observer, _ in
			let task = self.session.uploadTask(with: request, from: jsonData) { (data, response, error) in
				self.statusCodeResponseHandler(observer: observer, data: data, response: response, error: error) {}
			}
			task.resume()
		}.optionalLog("create net \(network)").observe(on: scheduler)
	}

	/// documentation in DockerAPI protocol
	func networkExists(name: String) -> SignalProducer<Bool, Rc2Error>
	{
		let req = URLRequest(url: baseUrl.appendingPathComponent("/networks"))
		return makeRequest(request: req)
			.flatMap(.concat, transform: { (data) -> SignalProducer<Bool, Rc2Error> in
				return SignalProducer<Bool, Rc2Error> { observer, _ in
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
	fileprivate func dataToJson(data: Data) -> SignalProducer<JSON, Rc2Error>
	{
		return SignalProducer<JSON, Rc2Error> { observer, _ in
			guard let json = try? JSON(data: data) else {
				observer.send(error: Rc2Error(type: .invalidJson))
				return
			}
			observer.send(value: json)
			observer.sendCompleted()
		}
	}

	/// parses JSON from docker daemon into version information
	///
	/// - parameter json: json object with version information
	///
	/// - returns: the version information
	fileprivate func parseVersionInfo(json: JSON) -> SignalProducer<DockerVersion, Rc2Error>
	{
		return SignalProducer<DockerVersion, Rc2Error> { observer, _ in
			do {
				os_log("parsing version info: %{public}@", log: .docker, type: .debug, try json.serializeString())
				let regex = try NSRegularExpression(pattern: "(\\d+)\\.(\\d+)\\.(\\d+)", options: [])
				let verStr = try json.getString(at: "Version")
				guard let match = regex.firstMatch(in: verStr, options: [], range: verStr.fullNSRange),
					let primaryVersion = Int((verStr as NSString).substring(with: match.rangeAt(1))),
					let secondaryVersion = Int((verStr as NSString).substring(with: match.rangeAt(2))),
					let fixVersion = Int((verStr as NSString).substring(with: match.rangeAt(3))),
					let apiStr = try? json.getString(at: "ApiVersion"),
					let apiVersion = Double(apiStr) else
				{
					observer.send(error: Rc2Error(type: .invalidJson))
					return
				}
				observer.send(value: DockerVersion(major: primaryVersion, minor: secondaryVersion, fix: fixVersion, apiVersion: apiVersion))
				observer.sendCompleted()
			} catch let err as NSError {
				observer.send(error: Rc2Error(type: .cocoa, nested: err))
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

	/// handles sending completed or error for a docker response based on http status code
	func statusCodeResponseHandler<T>(observer: Observer<T, Rc2Error>, data: Data?, response: URLResponse?, error: Error?, valueHandler:(() -> Void))
	{
		guard let rsp = response as? HTTPURLResponse, error == nil else {
			os_log("api remote error: %{public}@", log: .docker, type: .default, error! as NSError)
			observer.send(error: Rc2Error(type: .network, nested: error!))
			return
		}
		os_log("api status: %d", log: .docker, type: .debug, rsp.statusCode)
		switch rsp.statusCode {
		case 201, 204, 304: //spec says 204, but should be 201 for created. we'll handle both
			valueHandler()
			observer.sendCompleted()
		case 404:
			observer.send(error: Rc2Error(type: .network, nested: DockerError.noSuchObject))
		case 409:
			fallthrough
		default:
			observer.send(error: Rc2Error(type: .network, nested: DockerError.httpError(statusCode: rsp.statusCode, description: nil, mimeType: nil)))
		}
	}

	/// takes the data from a request and allows easy filtering of it
	///
	/// - parameter observer: the observer to send signals on
	/// - parameter data:     the data from a GET request
	/// - parameter filter:   a closure that determines if the json meets requirements
	func jsonCheckHandler(observer: Observer<Bool, Rc2Error>, data: Data?, filter: ((JSON) throws -> Bool))
	{
		guard let data = data else {
			observer.send(error: Rc2Error(type: .invalidArgument, explanation: "no data"))
			return
		}
		var json: JSON?
		var result: Bool = false
		do {
			json = try JSON(data: data)
			result = try filter(json!)
		} catch {
			observer.send(error: Rc2Error(type: .invalidJson, nested: error)) //is this really the best error?
			return
		}
		observer.send(value: result)
		observer.sendCompleted()
	}

	//must not reference self
	fileprivate func parseContainers(json: JSON) -> SignalProducer<[DockerContainer], Rc2Error>
	{
		do {
			let containers: [DockerContainer] = try json.decodedArray()
			return SignalProducer<[DockerContainer], Rc2Error>(value: containers)
		} catch {
			return SignalProducer<[DockerContainer], Rc2Error>(error: Rc2Error(type: .invalidJson, nested: error))
		}
	}

	fileprivate func parseImages(json: JSON) -> SignalProducer<[DockerImage], Rc2Error>
	{
		guard let images = try? json.getArray().flatMap({ (imgJson: JSON) -> DockerImage? in
			guard let img = try? DockerImage(json: imgJson) else { return nil }
			return img
		}) else {
			return SignalProducer<[DockerImage], Rc2Error>(error: Rc2Error(type: .invalidJson))
		}
		return SignalProducer<[DockerImage], Rc2Error> { observer, _ in
			let filteredImages = images.filter({ $0.labels.keys.contains("io.rc2.type") && $0.tags.count > 0 })
			observer.send(value: filteredImages)
			observer.sendCompleted()
		}
	}

	@discardableResult
	fileprivate func makeRequest(request: URLRequest) -> SignalProducer<Data, Rc2Error>
	{
		return SignalProducer<Data, Rc2Error> { observer, _ in
			self.session.dataTask(with: request, completionHandler: { (data, response, error) in
				guard let rawData = data, error == nil else {
					observer.send(error: Rc2Error(type: .network, nested: error))
					return
				}
				if rawData.count == 0 {
					print("no data")
				}
				//default to 200 for non-http status codes (such as file urls)
				let statusCode = response?.httpResponse?.statusCode ?? 200
				guard statusCode >= 200 && statusCode < 400 else {
					let rsp = response!.httpResponse!
					os_log("docker request got bad status: %d response = %{public}s", log: .docker, rsp.statusCode, String(data: data!, encoding: .utf8)!)
					let httpError = DockerError.generateHttpError(from: rsp, body: data)
					observer.send(error: Rc2Error(type: .docker, nested: httpError))
					return
				}
				observer.send(value: rawData)
				observer.sendCompleted()
			}).resume()
		}
	}
}
