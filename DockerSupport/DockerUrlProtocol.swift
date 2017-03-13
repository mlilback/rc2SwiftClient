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

///DockerUrlProtocol is a subclass of NSURLProtocol for dealing with "unix" URLs
/// This is used to communicate with the local Docker daemon using a REST-like syntax

open class DockerUrlProtocol: URLProtocol, URLSessionDelegate {
	fileprivate let socketPath = "/var/run/docker.sock"
	fileprivate let crlnData = Data(bytes: [UInt8(13), UInt8(10)])
	fileprivate var chunkHandler: LinedJsonHandler?

	override open class func canInit(with request: URLRequest) -> Bool {
		os_log("DUP queried about %{public}s", log: .docker, type: .debug, "\(request)")
		return request.url!.scheme == "unix"
	}

	open override class func canonicalRequest(for request: URLRequest) -> URLRequest {
		return request
	}

	override open func startLoading() {
		//do not allow to be used from a unit test. All calls to docker should be mocked
		guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { fatalError("mock all docker calls") }

		guard let fd = try? openDockerConnection() else { return }

		let fh = FileHandle(fileDescriptor: fd)
		guard let outStr = buildRequestString(), outStr.characters.count > 0 else { return }
		os_log("sending request to docker: %{public}s", log: .docker, type: .debug, outStr)
		fh.write(outStr.data(using: String.Encoding.utf8)!)
		if let body = request.httpBody {
			fh.write(body)
		} else if let bstream = request.httpBodyStream {
			fh.write(Data(bstream))
		}

		if request.isChunkedResponse {
			handleChunkedResponse(fileHandle: fh)
			return
		}
		let inData = fh.readDataToEndOfFile()
		close(fd)
		guard let (response, responseData) = processInitialResponse(data: inData) else { return }
		//report success to client
		client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
		client?.urlProtocol(self, didLoad: responseData)
		client?.urlProtocolDidFinishLoading(self)
	}

	// required by protocol, even though we don't use
	override open func stopLoading() {
		chunkHandler = nil
	}

	// MARK: - private methods

	/// Builds a string with the proper http request string
	///
	/// - returns: the string to use as an http request
	func buildRequestString() -> String? {
		guard var path = request.url?.path else { reportBadResponse(); return nil }
		if let queryStr = request.url?.query {
			path += "?\(queryStr)"
		}
		var outStr = "\(request.httpMethod!) \(path) HTTP/1.0\r\n"
		request.allHTTPHeaderFields?.forEach { (k, v) in
			outStr += "\(k): \(v)\r\n"
		}
		outStr += "\r\n"
		return outStr
	}

	/// actually write data to the file handle. Exists to allow unit test ignore write
	///
	/// - parameter data:       the data to write
	/// - parameter fileHandle: the file handle to write to
	func writeRequestData(data: Data, fileHandle: FileHandle) {
		fileHandle.write(data)
	}

	/// called to read rest of data as chunks
	///
	/// - parameter fileHandle: the fileHandle to asynchronously read chunks of data from
	fileprivate func handleChunkedResponse(fileHandle: FileHandle) {
		chunkHandler = LinedJsonHandler(fileHandle: fileHandle, handler: chunkedResponseHandler)
		chunkHandler?.start()
	}

	fileprivate func chunkedResponseHandler(msgType: MessageType, json: [JSON]) {
		switch msgType {
		case .complete:
			client?.urlProtocolDidFinishLoading(self)
		case .error:
			client?.urlProtocol(self, didFailWithError: Rc2Error(type: .invalidJson))
		case .json:
			var jdata = Data()
			json.forEach { aLine in
				// swiftlint:disable:next force_try
				jdata.append(try! aLine.serialize())
				jdata.append(crlnData)
			}
			client?.urlProtocol(self, didLoad: jdata)
		case .headers(let headData):
			guard let response = generateResponse(headerData: headData) else {
				client?.urlProtocol(self, didFailWithError: Rc2Error(type: .network))
				return
			}
			client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
		}
	}
	
	/// parses the incoming data and forwards it to the client
	///
	/// - parameter data: the data to parse
	///
	/// - throws: NSError if failed to parse the data. The error will have been reported to the client
	func processData(data: Data) throws {
		guard let (response, initialData) = processInitialResponse(data: data) else {
			reportBadResponse()
			return
		}
		//tell the client
		client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
		client?.urlProtocol(self, didLoad: initialData)
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
		os_log("connection open to docker %{public}s", log: .docker, type: .debug, request.url!.absoluteString)
		return fd
	}

	/// Parses the initial headers/content data from docker
	///
	/// - parameter inData: the data sent by docker
	///
	/// - returns: a response and the response data
	func processInitialResponse(data inData: Data) -> (HTTPURLResponse, Data)? {
		//split the response into headers and content, create a response object
		guard let (headData, contentData) = try? HttpStringUtils.splitResponseData(inData),
			let response = generateResponse(headerData: headData)
			else
		{
			reportBadResponse()
			return nil
		}
		return (response, contentData)
	}

	fileprivate func generateResponse(headerData: Data) -> HTTPURLResponse? {
		guard let headString = String(data: headerData, encoding: .utf8),
			let (statusCode, httpVersion, headers) = try? HttpStringUtils.extractHeaders(headString)
			else
		{
			return nil
		}
		os_log("docker returned %d", log: .docker, type: .debug, statusCode)
		guard let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: httpVersion, headerFields: headers) else
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
