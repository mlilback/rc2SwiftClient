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

/// Default implementation of DockerAPI protocol
final class DockerAPIImplementation: DockerAPI {
	// MARK: - properties
	public let baseUrl: URL
	fileprivate let sessionConfig: URLSessionConfiguration
	fileprivate var session: URLSession
	fileprivate let log: OSLog
	public let scheduler: QueueScheduler

	// MARK: - init

	/// Instantiates object to make calls to docker daemon
	///
	/// - parameter baseUrl:       The base URL of the docker socket (e.g. "http://..." or "unix://...")
	/// - parameter sessionConfig: configuration to use for httpsession, defaults to .default
	/// - parameter log:           the log object to use for os_log, defaults to sensible one
	///
	/// - returns: an instance of this class
	init(baseUrl: URL = URL(string: "unix://")!, sessionConfig: URLSessionConfiguration = URLSessionConfiguration.default, log: OSLog = OSLog(subsystem: "io.rc2.client", category: "docker"))
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
		self.log = log
	}

	// MARK: - general

	// documentation in DockerAPI protocol
	public func loadVersion() -> SignalProducer<DockerVersion, DockerError>
	{
		let req = URLRequest(url: baseUrl.appendingPathComponent("/version"))
		return makeRequest(request: req)
			.map({ $0.0 }) //transform from (Data, HTTPURLResponse) to Data
			.flatMap(.concat, transform: dataToJson)
			.flatMap(.concat, transform: parseVersionInfo)
			.observe(on: scheduler)
	}

	// documentation in DockerAPI protocol
	public func fetchJson(url: URL) -> SignalProducer<JSON, DockerError> {
		return self.makeRequest(request: URLRequest(url: url))
			.map({ $0.0 })
			.flatMap(.concat, transform: self.dataToJson)
	}

	// MARK: - image operations

	// documentation in DockerAPI protocol
	public func loadImages() -> SignalProducer<[DockerImage], DockerError> {
		let req = URLRequest(url: baseUrl.appendingPathComponent("/images/json"))
		return makeRequest(request: req)
			.map({ $0.0 })
			.flatMap(.concat, transform: dataToJson)
			.flatMap(.concat, transform: parseImages)
			.observe(on: scheduler)
	}

	// MARK: - volume operations

	public func volumeExists(name: String) -> SignalProducer<Bool, DockerError> {
		// swiftlint:disable:next force_try // we created from static string, serious programmer error if fails
		let filtersJson = try! JSONSerialization.data(withJSONObject: ["name": [name]], options: [])
		let filtersStr = String(data:filtersJson, encoding:.utf8)!
		var urlcomponents = URLComponents(url: self.baseUrl.appendingPathComponent("/volumes"), resolvingAgainstBaseURL: true)!
		urlcomponents.queryItems = [URLQueryItem(name:"all", value:"1"), URLQueryItem(name:"filters", value:filtersStr)]
		let req = URLRequest(url: urlcomponents.url!)

		return makeRequest(request: req)
			.map({ $0.0 }) //transform from (Data, HTTPURLResponse) to Data
			.flatMap(.concat, transform: { (data) -> SignalProducer<Bool, DockerError> in
				return SignalProducer<Bool, DockerError> { observer, _ in
					self.jsonCheckHandler(observer: observer, data: data) { json in
						let filteredVolumes = try json.getArray(at: "Volumes").filter( { aVolume in
							return try aVolume.getString(at: "Name") == name
						})
						return filteredVolumes.count == 1
					}
				}
			}).observe(on: scheduler)
	}

	/// documentation in DockerAPI protocol
	func create(volume: String) -> SignalProducer<(), DockerError>
	{
		var props = [String:Any]()
		props["Name"] = volume
		props["Labels"] = ["rc2.live": ""]
		// swiftlint:disable:next force_try
		let jsonData = try! JSONSerialization.data(withJSONObject: props, options: [])
		var request = URLRequest(url: baseUrl.appendingPathComponent("/volumes/create"))
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		return SignalProducer<(), DockerError> { observer, _ in
			let task = self.session.uploadTask(with: request, from: jsonData) { (data, response, error) in
				self.statusCodeResponseHandler(observer: observer, data: data, response: response, error: error) {
					observer.send(value: ())
				}
			}
			task.resume()
		}.observe(on: scheduler)
	}

	// MARK: - container operations

	// documentation in DockerAPI protocol
	public func refreshContainers() -> SignalProducer<[DockerContainer], DockerError>
	{
		return self.makeRequest(request: self.containersRequest())
			.map({ $0.0 }) //transform from (Data, HTTPURLResponse) to Data
			.flatMap(.concat, transform: dataToJson)
			.flatMap(.concat, transform: parseContainers)
			.observe(on: scheduler)
	}

	// documentation in DockerAPI protocol
	public func perform(operation: DockerContainerOperation, containers: [DockerContainer]) -> SignalProducer<(), DockerError>
	{
		let producers = containers
			.map({ self.perform(operation: operation, container: $0) })
		let producer = SignalProducer< SignalProducer<(), DockerError>, DockerError >(values: producers)
		return producer.flatten(.concat)
	}

	// documentation in DockerAPI protocol
	public func perform(operation: DockerContainerOperation, container: DockerContainer) -> SignalProducer<Void, DockerError>
	{
		let url = baseUrl.appendingPathComponent("/containers/\(container.name)/\(operation.rawValue)")
		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		return SignalProducer<Void, DockerError> { observer, disposable in
			self.session.dataTask(with: request) { (data, response, error) in
				self.statusCodeResponseHandler(observer: observer, data: data, response: response, error: error) {
					observer.send(value: ())
				}
			}.resume()
		}.observe(on: scheduler)
	}

	// documentation in DockerAPI protocol
	func create(container: DockerContainer) -> SignalProducer<DockerContainer, DockerError> {
		return SignalProducer<DockerContainer, DockerError> { observer, _ in
			guard container.state.value == .notAvailable else {
				observer.send(value: container)
				observer.sendCompleted()
				return
			}
			guard let jsonData = container.createInfo else {
				observer.send(error: .invalidJson)
				return
			}
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
		}
	}

	/// documentation in DockerAPI protocol
	func remove(container: DockerContainer) -> SignalProducer<(), DockerError> {
		let url = baseUrl.appendingPathComponent("/containers/\(container.name)")
		var request = URLRequest(url: url)
		request.httpMethod = "DELETE"
		return SignalProducer<Void, DockerError> { observer, _ in
			self.session.dataTask(with: request) { (data, response, error) in
				self.statusCodeResponseHandler(observer: observer, data: data, response: response, error: error) {
					observer.send(value: ())
				}
			}.resume()
		}.observe(on: scheduler)
	}

	// MARK: - network operations

	/// documentation in DockerAPI protocol
	func create(network: String) -> SignalProducer<(), DockerError>
	{
		var props = [String:Any]()
		props["Internal"] = true
		props["Driver"] = "bridge"
		props["Name"] = network
		// swiftlint:disable:next force_try
		let jsonData = try! JSONSerialization.data(withJSONObject: props, options: [])
		var request = URLRequest(url: baseUrl.appendingPathComponent("/networks/create"))
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		return SignalProducer<(), DockerError> { observer, _ in
			let task = self.session.uploadTask(with: request, from: jsonData) { (data, response, error) in
				self.statusCodeResponseHandler(observer: observer, data: data, response: response, error: error) {
					observer.send(value: ())
				}
			}
			task.resume()
		}.observe(on: scheduler)
	}

	/// documentation in DockerAPI protocol
	func networkExists(name: String) -> SignalProducer<Bool, DockerError> {
		let req = URLRequest(url: baseUrl.appendingPathComponent("/networks"))
		return makeRequest(request: req)
			.map({ $0.0 }) //transform from (Data, HTTPURLResponse) to Data
			.flatMap(.concat, transform: { (data) -> SignalProducer<Bool, DockerError> in
				return SignalProducer<Bool, DockerError> { observer, _ in
					self.jsonCheckHandler(observer: observer, data: data) { json in
						guard let networks = try? json.asJsonArray() else { return false }
						//nets is now json cast safely to [JSON]
						let matches = networks.flatMap { network -> JSON? in
							guard let itemName = try? network.getString(at: "Name") else { return nil }
							if itemName == name { return network }
							return nil
						}
						return matches.count == 1
					}
				}
			}).observe(on: scheduler)
	}
}

// MARK: private methods
extension DockerAPIImplementation {
	/// convience method to parse Data into JSON
	///
	/// - parameter data: data to parse
	///
	/// - returns: parsed JSON
	fileprivate func dataToJson(data: Data) -> SignalProducer<JSON, DockerError> {
		return SignalProducer<JSON, DockerError> { observer, _ in
			guard let json = try? JSON(data: data) else {
				observer.send(error: DockerError.invalidJson)
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
	fileprivate func parseVersionInfo(json: JSON) -> SignalProducer<DockerVersion, DockerError>
	{
		return SignalProducer<DockerVersion, DockerError> { observer, _ in
			do {
				let regex = try NSRegularExpression(pattern: "(\\d+)\\.(\\d+)\\.(\\d+)", options: [])
				let verStr = try json.getString(at: "Version")
				guard let match = regex.firstMatch(in: verStr, options: [], range: verStr.fullNSRange),
					let primaryVersion = Int((verStr as NSString).substring(with: match.rangeAt(1))),
					let secondaryVersion = Int((verStr as NSString).substring(with: match.rangeAt(2))),
					let fixVersion = Int((verStr as NSString).substring(with: match.rangeAt(3))),
					let apiStr = try? json.getString(at: "ApiVersion"),
					let apiVersion = Double(apiStr) else
				{
					observer.send(error: .invalidJson)
					return
				}
				observer.send(value: DockerVersion(major: primaryVersion, minor: secondaryVersion, fix: fixVersion, apiVersion: apiVersion))
				observer.sendCompleted()
			} catch let err as NSError {
				observer.send(error: .cocoaError(err))
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
	func statusCodeResponseHandler<T>(observer: Observer<T, DockerError>, data: Data?, response: URLResponse?, error: Error?, valueHandler:(() -> Void))
	{
		guard let rsp = response as? HTTPURLResponse, error == nil else {
			observer.send(error: .networkError(error as? NSError))
			return
		}
		switch rsp.statusCode {
		case 201, 204, 304: //spec says 204, but should be 201 for created. we'll handle both
			valueHandler()
			observer.sendCompleted()
		case 404:
			observer.send(error: .noSuchObject)
		case 409:
			observer.send(error: .alreadyExists)
		default:
			observer.send(error: .networkError(nil))
		}
	}

	/// takes the data from a request and allows easy filtering of it
	///
	/// - parameter observer: the observer to send signals on
	/// - parameter data:     the data from a GET request
	/// - parameter filter:   a closure that determines if the json meets requirements
	func jsonCheckHandler(observer: Observer<Bool, DockerError>, data: Data?, filter: ((JSON) throws -> Bool))
	{
		guard let rdata = data,
			let json = try? JSON(data: rdata),
			let result = try? filter(json) else
		{
			observer.send(error: .invalidJson) //is this really the best error?
			return
		}
		observer.send(value: result)
		observer.sendCompleted()
	}

	//must not reference self
	fileprivate func parseContainers(json: JSON) -> SignalProducer<[DockerContainer], DockerError>
	{
		guard let containers: [DockerContainer] = try? json.asArray() else {
			return SignalProducer<[DockerContainer], DockerError>(error: .invalidJson)
		}
		return SignalProducer<[DockerContainer], DockerError>(value: containers)
	}

	fileprivate func parseImages(json: JSON) -> SignalProducer<[DockerImage], DockerError> {
		guard let images: [DockerImage] = try? json.asArray() else {
			return SignalProducer<[DockerImage], DockerError>(error: .invalidJson)
		}
		return SignalProducer<[DockerImage], DockerError> { observer, _ in
			let filteredImages = images.filter({ $0.labels.keys.contains("io.rc2.type") && $0.tags.count > 0 })
			observer.send(value: filteredImages)
			observer.sendCompleted()
		}
	}

	@discardableResult
	fileprivate func makeRequest(request: URLRequest) -> SignalProducer<(Data, HTTPURLResponse), DockerError> {
		return SignalProducer<(Data, HTTPURLResponse), DockerError> { observer, disposable in
			self.session.dataTask(with: request, completionHandler: { (data, response, error) in
				guard let rawData = data, let rsp = response as? HTTPURLResponse, error == nil else {
					observer.send(error: .networkError(error as? NSError))
					return
				}
				guard rsp.statusCode >= 200 && rsp.statusCode < 400 else {
					observer.send(error: DockerError.generateHttpError(from: rsp, body: data))
					return
				}
				observer.send(value: (rawData, rsp))
				observer.sendCompleted()
			}).resume()
		}
	}
}