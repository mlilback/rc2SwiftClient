//
//  DockerAPIImplementation.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import ReactiveSwift
import SwiftyJSON
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
				guard let hresponse = response as? HTTPURLResponse, error == nil else {
					observer.send(error: .networkError(error as? NSError))
					return
				}
				switch hresponse.statusCode {
				case 204, 304:
					observer.sendCompleted()
				case 404:
					observer.send(error: .noSuchObject)
				default:
					observer.send(error: .networkError(error as? NSError))
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
			guard var containerJson = container.createInfo else {
				observer.send(error: .invalidJson)
				return
			}
			containerJson["Labels"] = JSON(["rc2.live": ""])
			// swiftlint:disable:next force_try // we created from static string, serious programmer error if fails
			let jsonData = try! containerJson.rawData()
			var comps = URLComponents(url: URL(string:"/containers/create", relativeTo:self.baseUrl)!, resolvingAgainstBaseURL: true)!
			comps.queryItems = [URLQueryItem(name:"name", value:container.name)]
			var request = URLRequest(url: comps.url!)
			request.httpMethod = "POST"
			request.setValue("application/json", forHTTPHeaderField: "Content-Type")
			let task = self.session.uploadTask(with: request, from: jsonData) { (data, response, error) in
				guard nil == error else {
					observer.send(error: .networkError(error! as NSError))
					return
				}
				print("create=\(String(data:data!, encoding:.utf8))")
				guard let response = response as? HTTPURLResponse else { fatalError("got non-http response") }
				switch response.statusCode {
				case 201: //success
					observer.send(value: container)
					observer.sendCompleted()
				case 409:
					observer.send(error: .alreadyExists)
				default:
					observer.send(error: DockerError.generateHttpError(from: response, body: data))
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
				guard let hresponse = response as? HTTPURLResponse, error == nil else {
					observer.send(error: .networkError(error as? NSError))
					return
				}
				switch hresponse.statusCode {
				case 204:
					observer.sendCompleted()
				case 404:
					observer.send(error: .noSuchObject)
				case 409:
					observer.send(error: .conflict)
				default:
					observer.send(error: .networkError(error as? NSError))
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
				guard let rsp = response as? HTTPURLResponse, error == nil else {
					observer.send(error: .networkError(error as? NSError))
					return
				}
				switch rsp.statusCode {
					case 201, 204: //spec says 204, but should be 201 for created. we'll handle both
						observer.sendCompleted()
					case 404:
						observer.send(error: .noSuchObject)
					default:
						observer.send(error: .networkError(nil))
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
					guard let jsonStr = String(data: data, encoding: .utf8) else {
						observer.send(error: .invalidJson)
						return
					}
					let json = JSON.parse(jsonStr)
					observer.send(value: json.arrayValue.filter( { aNet in
						return aNet["Name"].stringValue == name
					}).count > 0)
					observer.sendCompleted()
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
			guard let jsonStr = String(data: data, encoding:.utf8) else {
				observer.send(error: .invalidJson)
				return
			}
			observer.send(value: JSON.parse(jsonStr))
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
				let verStr = json["Version"].stringValue
				guard let match = regex.firstMatch(in: verStr, options: [], range: verStr.fullNSRange),
					let primaryVersion = Int((verStr as NSString).substring(with: match.rangeAt(1))),
					let secondaryVersion = Int((verStr as NSString).substring(with: match.rangeAt(2))),
					let fixVersion = Int((verStr as NSString).substring(with: match.rangeAt(3))),
					let apiVersion = Double(json["ApiVersion"].stringValue) else
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

	//must not reference self
	fileprivate func parseContainers(json: JSON) -> SignalProducer<[DockerContainer], DockerError>
	{
		return SignalProducer<[DockerContainer], DockerError> { observer, _ in
			observer.send(value: json.arrayValue.flatMap { return DockerContainer(json:$0) })
			observer.sendCompleted()
		}
	}

	fileprivate func parseImages(json: JSON) -> SignalProducer<[DockerImage], DockerError> {
		return SignalProducer<[DockerImage], DockerError> { observer, _ in
			let images = json.arrayValue
				.flatMap({ DockerImage(json: $0) })
				.filter({ $0.labels.keys.contains("io.rc2.type") && $0.tags.count > 0 })
			observer.send(value: images)
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
