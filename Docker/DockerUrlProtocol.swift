//
//  DockerUrlProtocol.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Darwin
import os
import Freddy

///DockerUrlProtocol is a subclass of NSURLProtocol for dealing with "unix" and "dockerstream" URLs
/// This is used to communicate with the local Docker daemon using a REST-like syntax

public class DockerUrlProtocol: URLProtocol, URLSessionDelegate {
	public static let scheme = "unix"
	/// for "hijacked" streams that stay open and keep sending data
	public static let streamScheme = "dockerstream"
	private var connection: LocalDockerConnection?

	override open class func canInit(with request: URLRequest) -> Bool {
		os_log("DUP queried about %{public}@", log: .docker, type: .debug, request.url!.absoluteString)
		return request.url!.scheme == scheme || request.url!.scheme == streamScheme
	}

	open override class func canonicalRequest(for request: URLRequest) -> URLRequest {
		return request
	}

	override open func startLoading() {
		//do not allow to be used from a unit test. All calls to docker should be mocked
		guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { fatalError("mock all docker calls") }

		if request.url!.scheme! == DockerUrlProtocol.streamScheme {
			connection = LocalDockerConnectionImpl<HijackedResponseHandler>(request: request, handler: responseCallback)
		} else {
			connection = LocalDockerConnectionImpl<SingleDataResponseHandler>(request: request, handler: responseCallback)
		}
		do {
			try connection?.openConnection()
		} catch {
			client?.urlProtocol(self, didFailWithError: error)
			return
		}
		connection?.writeRequest()
	}

	// required by protocol, even though we don't use
	override open func stopLoading() {
		connection?.closeConnection()
		connection = nil
	}

	fileprivate func responseCallback(msgType: LocalDockerMessage) {
		switch msgType {
		case .complete:
			client?.urlProtocolDidFinishLoading(self)
		case .error(let err):
			client?.urlProtocol(self, didFailWithError: err)
		case .headers(let headers):
			guard let response = generateResponse(headers: headers) else {
				client?.urlProtocol(self, didFailWithError: DockerError.networkError(nil)) //FIXME: better error reporting
				return
			}
			client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
		case .data(let data):
			client?.urlProtocol(self, didLoad: data)
		}
	}
	
	fileprivate func generateResponse(headers: HttpHeaders) -> HTTPURLResponse? {
		os_log("docker returned %d", log: .docker, type: .debug, headers.statusCode)
		guard let response = HTTPURLResponse(url: request.url!, statusCode: headers.statusCode, httpVersion: headers.httpVersion, headerFields: headers.headers) else
		{ return nil }
		return response
	}
}
