//
//  DockerUrlProtocol.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Darwin
import os
import Freddy
import ClientCore

///DockerUrlProtocol is a subclass of NSURLProtocol for dealing with "unix" and "dockerstream" URLs
/// This is used to communicate with the local Docker daemon using a REST-like syntax

public class DockerUrlProtocol: URLProtocol, URLSessionDelegate {
	public static let scheme = "unix"
	/// for "hijacked" streams that stay open and keep sending data
	public static let streamScheme = "dockerstream"
	fileprivate let socketPath = "/var/run/docker.sock"
	fileprivate let crlnData = Data(bytes: [UInt8(13), UInt8(10)])
	fileprivate var chunkHandler: DockerResponseHandler?

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

		guard let fd = try? openDockerConnection() else { return }
		let massagedRequest = massageRequest()
		guard let requestData = massagedRequest.CFHTTPMessage.serialized else { fatalError("failed to serialize request") }
//		let lenWritten = requestData.withUnsafeBytes { (data) -> Int in
//			return write(fd, data, requestData.count)
//		}
//		guard lenWritten == requestData.count else { fatalError() }
		let fh = FileHandle(fileDescriptor: fd)
		writeRequestData(data: requestData, fileHandle: fh)
		if let body = request.httpBody {
			writeRequestData(data: body, fileHandle: fh)
		} else if let bstream = request.httpBodyStream {
			writeRequestData(data: Data(bstream), fileHandle: fh)
		}
		queueResponseHandler(fileDescriptor: fd)
	}

	// required by protocol, even though we don't use
	override open func stopLoading() {
		chunkHandler = nil
	}

	// MARK: - private methods

	/// modifies request for use as a docker request
	func massageRequest() -> URLRequest {
		guard let origUrl = request.url, var components = URLComponents(url: origUrl, resolvingAgainstBaseURL: true)
			else { fatalError("request must have URL") }
		if !components.path.hasPrefix("/") {
			components.path = "/\(components.path)"
		}
		guard let newUrl = components.url else { fatalError("failed to generate new url") }
		var req = request
		req.url = newUrl
		req.addValue("localhost:8088", forHTTPHeaderField: "Host")
		req.addValue("close", forHTTPHeaderField: "Connection")
		req.addValue("Rc2Engine", forHTTPHeaderField: "User-Agent")
		if request.isHijackedResponse {
			req.addValue("*/*", forHTTPHeaderField: "Accept")
		}
//		req.addValue("chunked", forHTTPHeaderField: "Transfer-Encoding")
		return req
	}
	
	/// actually write data to the file handle. Exists to allow unit test ignore write
	///
	/// - parameter data:       the data to write
	/// - parameter fileHandle: the file handle to write to
	func writeRequestData(data: Data, fileHandle: FileHandle) {
		fileHandle.write(data)
	}

	fileprivate func queueResponseHandler(fileDescriptor: Int32) {
		if request.url!.scheme! == DockerUrlProtocol.streamScheme {
			chunkHandler = HijackedResponseHandler(fileDescriptor: fileDescriptor, queue: DispatchQueue.global(), handler: responseCallback)
		} else {
			chunkHandler = SingleDataResponseHandler(fileDescriptor: fileDescriptor, queue: DispatchQueue.global(), handler: responseCallback)
		}
		chunkHandler?.startHandler()
	}

	fileprivate func responseCallback(msgType: MessageType) {
		switch msgType {
		case .complete:
			client?.urlProtocolDidFinishLoading(self)
		case .error(let err):
			client?.urlProtocol(self, didFailWithError: err)
		case .json(let json):
			var jdata = Data()
			json.forEach { aLine in
				// swiftlint:disable:next force_try
				jdata.append(try! aLine.serialize())
				jdata.append(crlnData)
			}
			client?.urlProtocol(self, didLoad: jdata)
		case .headers(let headers):
			guard let response = generateResponse(headers: headers) else {
				client?.urlProtocol(self, didFailWithError: Rc2Error(type: .network))
				return
			}
			client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
		case .data(let data):
			client?.urlProtocol(self, didLoad: data)
		}
	}
	
	/// Opens a socket to docker daemon. Notifies user of any problems
	///
	/// - throws: an NSError that has been reported to the client
	///
	/// - returns: the file descriptor for the connection
	fileprivate func openDockerConnection() throws -> Int32 {
		let fd = socket(AF_UNIX, SOCK_STREAM, 0)
		guard fd >= 0 else {
			let error = NSError(domain: NSPOSIXErrorDomain, code: Int(Darwin.errno), userInfo: nil)
			client?.urlProtocol(self, didFailWithError: error)
			throw error
		}
		let pathLen = socketPath.utf8CString.count
		precondition(pathLen < 104) //size limit of struct
		var addr = sockaddr_un()
		addr.sun_family = sa_family_t(AF_LOCAL)
		addr.sun_len = UInt8(pathLen)
		_ = withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
			strncpy(UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self), socketPath, pathLen)
		}
		//connect, make the request, and fetch result data
		var code: Int32 = 0
		withUnsafePointer(to: &addr) { ptr in
			ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { ar in
				code = connect(fd, ar, socklen_t(MemoryLayout<sockaddr_un>.size))
			}
		}
		guard code >= 0 else {
			os_log("bad response %d, %d", type:.error, code, errno)
			let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorBadServerResponse, userInfo: [NSURLErrorFailingURLStringErrorKey: request.url!])
			reportBadResponse(error: error)
			throw error
		}
		os_log("connection open to docker %{public}@", log: .docker, type: .debug, request.url!.absoluteString)
		return fd
	}

	fileprivate func generateResponse(headers: HttpHeaders) -> HTTPURLResponse? {
		os_log("docker returned %d", log: .docker, type: .debug, headers.statusCode)
		guard let response = HTTPURLResponse(url: request.url!, statusCode: headers.statusCode, httpVersion: headers.httpVersion, headerFields: headers.headers) else
		{ return nil }
		return response
	}
	
	//convience wrapper for sending an error message to the client
	fileprivate func reportBadResponse(error: NSError? = nil) {
		var terror = error
		if terror == nil {
			terror = NSError(domain: NSURLErrorDomain, code: NSURLErrorBadServerResponse, userInfo: [NSURLErrorFailingURLStringErrorKey: request.url!])
		}
		client?.urlProtocol(self, didFailWithError: terror!)
	}
}
