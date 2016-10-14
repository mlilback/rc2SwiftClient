//
//  DockerAPIImplementation.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import ReactiveSwift
import SwiftyJSON
import os

public extension SignalProducer {
	public func passValue<U>(to link: @escaping ((Value) -> SignalProducer<U, Error>)) -> SignalProducer<U, Error>
	{
		return SignalProducer<U, Error> { observer, _ in
			self.startWithResult { firstResult in
				switch firstResult {
				case .success(let firstValue):
					link(firstValue).startWithResult { secondResult in
						switch secondResult {
						case .success(let secondValue):
							observer.send(value: secondValue)
							observer.sendCompleted()
						case .failure(let secondError):
							observer.send(error: secondError)
						}
					}
				case .failure(let firstError):
					observer.send(error: firstError)
				}
			}
		}
	}
}

class DockerAPIImplementation: DockerAPI {
	fileprivate let baseUrl: URL
	fileprivate let sessionConfig: URLSessionConfiguration
	fileprivate var session: URLSession
	fileprivate let log: OSLog

	init(baseUrl: URL, sessionConfig: URLSessionConfiguration = URLSessionConfiguration.default, log: OSLog = OSLog(subsystem: "io.rc2.client", category: "docker"))
	{
		self.baseUrl = baseUrl
		self.sessionConfig = sessionConfig
		sessionConfig.protocolClasses = [DockerUrlProtocol.self] as [AnyClass] + sessionConfig.protocolClasses!
		sessionConfig.requestCachePolicy = .reloadIgnoringLocalCacheData
		session = URLSession(configuration: sessionConfig)
		self.log = log
	}

	/// - returns: a URLRequest to fetch list of containers
	public func containersRequest() -> URLRequest {
		// swiftlint:disable:next force_try
		let filtersJson = try! JSONSerialization.data(withJSONObject: ["label": ["rc2.live"]], options: [])
		let filtersStr = String(data:filtersJson, encoding:.utf8)!
		var urlcomponents = URLComponents(url: self.baseUrl.appendingPathComponent("/containers/json"), resolvingAgainstBaseURL: true)!
		urlcomponents.queryItems = [URLQueryItem(name:"all", value:"1"), URLQueryItem(name:"filters", value:filtersStr)]
		return URLRequest(url: urlcomponents.url!)
	}

	public func dataToContainers(data: Data) -> SignalProducer<[DockerContainer], NSError>
	{
		return SignalProducer<[DockerContainer], NSError> { observer, _ in
			guard let jsonStr = String(data: data, encoding:.utf8) else {
				observer.send(error: NSError.error(withCode: .invalidJson, description: "failed to parse as utf8 string"))
				return
			}
			let json = JSON.parse(jsonStr)
			observer.send(value: json.arrayValue.flatMap { return DockerContainer(json:$0) })
			observer.sendCompleted()
		}
	}

	/// Fetches the current containers from the docker daemon
	///
	/// - returns: a signal producer that will send a single value and a completed event, or an error event
	public func refreshContainers() -> SignalProducer<[DockerContainer], NSError> {
		return  self.makeRequest(request: self.containersRequest())
			.map({ $0.0 }) //transform from (Data, HTTPURLResponse) to Data
			.passValue(to: dataToContainers)
	}

	/// Performs an operation on a docker container
	///
	/// - parameter operation: the operation to perform
	/// - parameter container: the target container
	///
	/// - returns: a signal producer that will return no Next events
	func perform(operation: DockerContainerOperation, on container: DockerContainer) -> SignalProducer<Void, NSError>
	{
		let url = baseUrl.appendingPathComponent("/containers/\(container.name)/\(operation.rawValue)")
		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		return SignalProducer<Void, NSError> { observer, disposable in
			self.session.dataTask(with: request) { (data, response, error) in
				guard let hresponse = response as? HTTPURLResponse, error == nil else {
					observer.send(error: error as! NSError)
					return
				}
				switch hresponse.statusCode {
				case 204:
					observer.sendCompleted()
				case 304:
					observer.send(error: NSError.error(withCode: .alreadyExists, description: "operation already in progress"))
				case 404:
					observer.send(error: NSError.error(withCode: .noSuchObject, description: "no such container"))
				default:
					observer.send(error: NSError.error(withCode: .serverError, description: "unknown error"))
				}
			}
		}
	}

	@discardableResult
	func makeRequest(request: URLRequest) -> SignalProducer<(Data, HTTPURLResponse), NSError> {
		return SignalProducer<(Data, HTTPURLResponse), NSError> { observer, disposable in
			self.session.dataTask(with: request, completionHandler: { (data, response, error) in
				guard let rawData = data, let rsp = response as? HTTPURLResponse, error == nil else {
					observer.send(error: error as! NSError)
					return
				}
				guard rsp.statusCode == 200 else {
					let httperror = NSError.error(withCode: .serverError, description: "server returned \(rsp.statusCode) error", underlyingError: error as NSError?)
					observer.send(error: httperror)
					return
				}
				observer.send(value: (rawData, rsp))
				observer.sendCompleted()
			}).resume()
		}
	}
}
