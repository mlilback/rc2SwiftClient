//
//  DockerUrlProtocol.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Darwin
import os

///DockerUrlProtocol is a subclass of NSURLProtocol for dealing with "unix" URLs
/// This is used to communicate with the local Docker daemon using a REST-like syntax

open class DockerUrlProtocol: URLProtocol, URLSessionDelegate {
	fileprivate let socketPath = "/var/run/docker.sock"
	fileprivate var chunkObserver: BackgroundReader?

	override open class func canInit(with request: URLRequest) -> Bool {
		os_log("DUP queried about %{public}s", log: .docker, type: .debug, "\(request)")
		return request.url!.scheme == "unix"
	}

	open override class func canonicalRequest(for request: URLRequest) -> URLRequest {
		return request
	}

	override open func startLoading() {
		guard let fd = try? openDockerConnection() else { return }

		let fh = FileHandle(fileDescriptor: fd)
		guard let outStr = buildRequestString(), outStr.characters.count > 0 else { return }
		fh.write(outStr.data(using: String.Encoding.utf8)!)
		if let body = request.httpBody {
			fh.write(body)
		} else if let bstream = request.httpBodyStream {
			fh.write(Data(bstream))
		}

		guard !request.isChunkedResponse else {
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

	// required by protocol, even though we don't user
	override open func stopLoading() {
		chunkObserver = nil
	}

	//MARK: - private methods

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
		//parse the first chunk of data that is available
		guard let _ = try? processData(data: fileHandle.availableData) else {
			print("failed to process initial data")
			return
		}

		//now start reading any future data asynchronously
		chunkObserver = BackgroundReader(owner: self, fileHandle: fileHandle)
		fileHandle.waitForDataInBackgroundAndNotify()
//		let queue = DispatchQueue.global(qos: .userInitiated)
//		let source = DispatchSource.makeReadSource(fileDescriptor: fileHandle.fileDescriptor, queue: queue)
//		source.setEventHandler {
//			self.client?.urlProtocol(self, didLoad: fileHandle.availableData)
//		}
//		source.setCancelHandler {
//			print("chunk canceled")
//			self.client?.urlProtocolDidFinishLoading(self)
//			fileHandle.closeFile()
//		}
//		source.activate()
		// FIXME: we're not doing the actual work right now
//		DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: DispatchTime.now() + 0.5) {
//			self.client?.urlProtocol(self, didLoad: "foo".data(using: .utf8)!)
//			DispatchQueue.global().async {
//				self.client?.urlProtocolDidFinishLoading(self)
//			}
//		}
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
			let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorBadServerResponse, userInfo: [NSURLErrorFailingURLStringErrorKey:request.url!])
			reportBadResponse(error: error)
			throw error
		}
		return fd
	}

	/// Parses the initial headers/content data from docker
	///
	/// - parameter inData: the data sent by docker
	///
	/// - returns: a response and the response data
	func processInitialResponse(data inData: Data) -> (HTTPURLResponse, Data)? {
		//split the response into headers and content, create a response object
		guard let (headersString, contentString) = splitResponseData(inData) else { reportBadResponse(); return nil }
		guard let (statusCode, httpVersion, headers) = extractHeaders(headersString) else { reportBadResponse(); return nil }
		guard let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: httpVersion, headerFields: headers) else { reportBadResponse(); return nil }
		return (response, contentString.data(using: String.Encoding.utf8)!)
	}

	//convience wrapper for sending an error message to the client
	fileprivate func reportBadResponse(error: NSError? = nil) {
		var terror = error
		if terror == nil {
			terror = NSError(domain: NSURLErrorDomain, code: NSURLErrorBadServerResponse, userInfo: [NSURLErrorFailingURLStringErrorKey:request.url!])
		}
		client?.urlProtocol(self, didFailWithError: terror!)
	}

	///splits raw data into headers and content
	///
	/// - parameter data: raw data to split
	/// - returns: a tuple of the header and content strings
	fileprivate func splitResponseData(_ data: Data) -> (String, String)? {
		guard let responseString = String(data:data, encoding: String.Encoding.utf8),
			let endFirstLineRange = responseString.range(of: "\r\n\r\n")
			else { reportBadResponse(); return nil }
		let headersString = responseString.substring(with: responseString.startIndex..<endFirstLineRange.lowerBound)
		let contentString = responseString.substring(from: endFirstLineRange.upperBound)
		return (headersString, contentString)
	}

	///extracts headers into a dictionary
	/// - parameter headerString: the raw headers from an HTTP response
	/// - returns: tuple of the HTTP status code, HTTP version, and a dictionary of headers
	func extractHeaders(_ responseString: String) -> (Int, String, [String:String])? {
		// swiftlint:disable:next force_try
		let responseRegex = try! NSRegularExpression(pattern: "^(HTTP/1.\\d) (\\d+)( .*?\r\n)(.*)", options: [.anchorsMatchLines, .dotMatchesLineSeparators])
		guard let matchResult = responseRegex.firstMatch(in: responseString, options: [], range: responseString.fullNSRange), matchResult.numberOfRanges == 5,
			let statusString = responseString.substring(from: matchResult.rangeAt(2)),
			let statusCode = Int(statusString),
			let versionString = responseString.substring(from: matchResult.rangeAt(1)),
			let headersString = responseString.substring(from: matchResult.rangeAt(4))
			else { reportBadResponse(); return nil }
		var headers = [String:String]()
		// swiftlint:disable:next force_try
		let headerRegex = try! NSRegularExpression(pattern: "(.+): (.*)", options: [])
		headerRegex.enumerateMatches(in: headersString, options: [], range: headersString.fullNSRange)
		{ (matchResult, _, _) in
			if let match = matchResult,
				let key = headersString.substring(from: match.rangeAt(1)),
				let value = headersString.substring(from: match.rangeAt(2))
			{
				headers[key] = value
			}
		}
		return (statusCode, versionString, headers)
	}
}

/// Reads data from a FileHandle and sends the data to a URLProtocol's client, finishing when EOF is reached
class BackgroundReader {
	weak var proto: URLProtocol?

	/// Creates an instance that reads data from fileHandle and forwards it to the owner's client, finishing when EOF is reached
	///
	/// - parameter owner:      the URLProtocol who's client should be notified of data and finish
	/// - parameter fileHandle: the fileHandle to read
	init(owner: URLProtocol, fileHandle: FileHandle) {
		self.proto = owner
		let nc = NotificationCenter.default
		nc.addObserver(self, selector: #selector(BackgroundReader.dataRead(note:)), name: Notification.Name.NSFileHandleDataAvailable, object: fileHandle)
	}

	/// Callback for NotificationCenter when data is available on the monitored FileHandle
	///
	/// - parameter note: the notification object
	@objc func dataRead(note: Notification) {
		guard let fh = note.object as? FileHandle else { fatalError() }
		let data = fh.availableData
		if data.count < 1 {
			proto?.client?.urlProtocolDidFinishLoading(proto!)
			return
		}
		proto?.client?.urlProtocol(proto!, didLoad: data)
		fh.waitForDataInBackgroundAndNotify()
	}
}
