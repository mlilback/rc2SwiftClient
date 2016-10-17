//
//  DockerAPIImplementation.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import ReactiveSwift
import SwiftyJSON
import os

/// Default implementation of DockerAPI protocol
class DockerAPIImplementation: DockerAPI {
	fileprivate let baseUrl: URL
	fileprivate let sessionConfig: URLSessionConfiguration
	fileprivate var session: URLSession
	fileprivate let log: OSLog

	/// Instantiates object to make calls to docker daemon
	///
	/// - parameter baseUrl:       The base URL of the docker socket (e.g. "http://..." or "unix://...")
	/// - parameter sessionConfig: configuration to use for httpsession, defaults to .default
	/// - parameter log:           the log object to use for os_log, defaults to sensible one
	///
	/// - returns: an instance of this class
	init(baseUrl: URL, sessionConfig: URLSessionConfiguration = URLSessionConfiguration.default, log: OSLog = OSLog(subsystem: "io.rc2.client", category: "docker"))
	{
		self.baseUrl = baseUrl
		self.sessionConfig = sessionConfig
		sessionConfig.protocolClasses = [DockerUrlProtocol.self] as [AnyClass] + sessionConfig.protocolClasses!
		sessionConfig.requestCachePolicy = .reloadIgnoringLocalCacheData
		session = URLSession(configuration: sessionConfig)
		self.log = log
	}

	// documentation in DockerAPI protocol
	public func refreshContainers() -> SignalProducer<[DockerContainer], DockerError>
	{
		return self.makeRequest(request: self.containersRequest())
			.map({ $0.0 }) //transform from (Data, HTTPURLResponse) to Data
			.flatMap(.concat, transform: dataToContainers)
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
		let url = baseUrl.appendingPathComponent("containers/\(container.name)/\(operation.rawValue)")
		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		return SignalProducer<Void, DockerError> { observer, disposable in
			self.session.dataTask(with: request) { (data, response, error) in
				guard let hresponse = response as? HTTPURLResponse, error == nil else {
					observer.send(error: .networkError(error as? NSError))
					return
				}
				switch hresponse.statusCode {
				case 204:
					observer.sendCompleted()
				case 304:
					observer.send(error: .alreadyInProgress)
				case 404:
					observer.send(error: .noSuchObject)
				default:
					observer.send(error: .networkError(error as? NSError))
				}
			}.resume()
		}
	}

	/// documentation in DockerAPI protocol
	func remove(container: DockerContainer) -> SignalProducer<(), DockerError> {
		let url = baseUrl.appendingPathComponent("containers/\(container.name)")
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
		}
	}
}

extension DockerAPIImplementation {
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

	//must not reference self so can be used as the target of passValue without a retain cycle
	fileprivate func dataToContainers(data: Data) -> SignalProducer<[DockerContainer], DockerError>
	{
		return SignalProducer<[DockerContainer], DockerError> { observer, _ in
			guard let jsonStr = String(data: data, encoding:.utf8) else {
				observer.send(error: .invalidJson)
				return
			}
			let json = JSON.parse(jsonStr)
			observer.send(value: json.arrayValue.flatMap { return DockerContainer(json:$0) })
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
