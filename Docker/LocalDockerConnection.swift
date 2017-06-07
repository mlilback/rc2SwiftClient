//
//  LocalDockerConnection.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Darwin
import os

enum LocalDockerMessage: Equatable {
	case headers(HttpHeaders), data(Data), complete, error(DockerError)
	
	static func == (a: LocalDockerMessage, b: LocalDockerMessage) -> Bool {
		switch (a, b) {
		case (.error(let e1), .error(let e2)):
			return e1 == e2
		case (.complete, .complete):
			return true
		case (.data(let d1), .data(let d2)):
			return d1 == d2
		case (.headers(let h1), .headers(let h2)):
			return h1 == h2
		default:
			return false
		}
	}
}

typealias DockerMessageHandler = (LocalDockerMessage) -> Void

protocol LocalDockerConnection: class {
	init(request: URLRequest, hijack: Bool, handler: @escaping DockerMessageHandler)
	@discardableResult
	func writeRequest() -> Bool
	func openConnection() throws
	func closeConnection()
}

final class LocalDockerConnectionImpl<HandlerClass: DockerResponseHandler>: LocalDockerConnection {
	fileprivate let socketPath = "/var/run/docker.sock"
	fileprivate let crlnData = Data(bytes: [UInt8(13), UInt8(10)])
	fileprivate var responseHandler: HandlerClass?
	fileprivate var request: URLRequest!
	fileprivate let handler: DockerMessageHandler
	fileprivate var fileDescriptor: Int32 = 0
	fileprivate let hijack: Bool
	
	required init(request: URLRequest, hijack: Bool = false, handler: @escaping DockerMessageHandler)
	{
		self.handler = handler
		self.hijack = hijack
		self.request = massage(request: request)
	}
	
	/// actually writes the request to the docker connection
	@discardableResult
	func writeRequest() -> Bool {
		precondition(fileDescriptor > 0) // must have called openConnection()
		guard let requestData = request.CFHTTPMessage.serialized else {
			handler(.error(.internalError("failed to serialize docker request")))
			return false
		}
		let fh = FileHandle(fileDescriptor: fileDescriptor)
		fh.write(requestData)
		if let body = request.httpBody {
			fh.write(body)
		} else if let bstream = request.httpBodyStream {
			fh.write(Data(bstream))
		}
		responseHandler?.startHandler()
		return true
	}
	
	/// opens the connection to the docker daemon
	func openConnection() throws {
		fileDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
		guard fileDescriptor >= 0 else {
			let rootError = NSError(domain: NSPOSIXErrorDomain, code: Int(Darwin.errno), userInfo: nil)
			handler(.error(.cocoaError(rootError)))
			throw DockerError.cocoaError(rootError)
		}
		let pathLen = socketPath.utf8CString.count
		precondition(pathLen < 104) //size limit of struct
		var addr = sockaddr_un()
		addr.sun_family = sa_family_t(AF_LOCAL)
		addr.sun_len = UInt8(pathLen)
		_ = withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
			strncpy(UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self), socketPath, pathLen)
		}
		//connect
		var code: Int32 = 0
		withUnsafePointer(to: &addr) { ptr in
			ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { ar in
				code = connect(fileDescriptor, ar, socklen_t(MemoryLayout<sockaddr_un>.size))
			}
		}
		guard code >= 0 else {
			os_log("bad response %d, %d", type:.error, code, errno)
			let rootError = NSError(domain: NSURLErrorDomain, code: NSURLErrorBadServerResponse, userInfo: [NSURLErrorFailingURLStringErrorKey: request.url!])
			handler(.error(.networkError(rootError)))
			throw DockerError.networkError(rootError)
		}
		os_log("connection open to docker %{public}@", log: .docker, type: .debug, request.url!.absoluteString)
		responseHandler = HandlerClass(fileDescriptor: fileDescriptor, queue: DispatchQueue.global(), handler: handler)
	}
	
	/// closes the connection to the docker daemon. handler will no longer receive any messages
	func closeConnection() {
		guard fileDescriptor > 0, responseHandler != nil else {
			os_log("closeConnection called when closed", log: .app)
			return
		}
//		precondition(fileDescriptor > 0)
//		precondition(responseHandler != nil, "connection already closed")
		close(fileDescriptor)
		fileDescriptor = 0
		responseHandler?.closeHandler()
		responseHandler = nil
	}

	/// modifies request for use as a docker request by adding headers
	private func massage(request: URLRequest) -> URLRequest {
		guard let origUrl = request.url, var components = URLComponents(url: origUrl, resolvingAgainstBaseURL: true)
			else { fatalError("request must have URL") }
		if !components.path.hasPrefix("/") {
			components.path = "/\(components.path)"
		}
		if components.path.range(of: "^/v1.2\\d/", options: .regularExpression) == nil {
			components.path = "/v1.27\(components.path)"
		}
		guard let newUrl = components.url else { fatalError("failed to generate new url") }
		var req = request
		req.url = newUrl
		req.addValue("localhost:8088", forHTTPHeaderField: "Host")
		if !hijack {
			req.addValue("close", forHTTPHeaderField: "Connection")
		}
		req.addValue("Rc2Engine", forHTTPHeaderField: "User-Agent")
		if request.isHijackedResponse {
			req.addValue("*/*", forHTTPHeaderField: "Accept")
		}
		if let body = req.httpBody {
			req.addValue("\(body.count)", forHTTPHeaderField: "Content-Length")
		}
		//		req.addValue("chunked", forHTTPHeaderField: "Transfer-Encoding")
		return req
	}
}
