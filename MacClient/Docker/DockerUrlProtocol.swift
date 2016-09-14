//
//  DockerUrlProtocol.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import ClientCore
import Darwin
import os

///DockerUrlProtocol is a subclass of NSURLProtocol for dealing with "unix" URLs
/// This is used to communicate with the local Docker daemon using a REST-like syntax

open class DockerUrlProtocol: URLProtocol, URLSessionDelegate {
	fileprivate let socketPath = "/var/run/docker.sock"
	
	override open class func canInit(with request:URLRequest) -> Bool {
		return request.url!.scheme == "unix"
	}
	
	open override class func canonicalRequest(for request:URLRequest) -> URLRequest {
		return request
	}
	
	override open func startLoading() {
		//setup a unix domain socket
		let fd = socket(AF_UNIX, SOCK_STREAM, 0)
		guard fd >= 0 else {
			client?.urlProtocol(self, didFailWithError: NSError(domain: NSPOSIXErrorDomain, code: Int(Darwin.errno), userInfo: nil))
			return
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
		var code:Int32 = 0
		withUnsafePointer(to: &addr) { ptr in
			ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { ar in
				code = connect(fd, ar, socklen_t(MemoryLayout<sockaddr_un>.size))
			}
		}
		guard code >= 0 else {
			os_log("bad response %d, %d", type:.error, code, errno)
			reportBadResponse()
			return
		}
		let fh = FileHandle(fileDescriptor: fd)
		guard let path = request.url?.path else { reportBadResponse(); return }
		let outStr = "GET \(path) HTTP/1.0\r\n\r\n"
		fh.write(outStr.data(using: String.Encoding.utf8)!)
		let inData = fh.readDataToEndOfFile()
		close(fd)
		
		//split the response into headers and content, create a response object
		guard let (headersString, contentString) = splitResponseData(inData) else { reportBadResponse(); return }
		guard let (statusCode, httpVersion, headers) = extractHeaders(headersString) else { reportBadResponse(); return }
		guard let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: httpVersion, headerFields: headers) else { reportBadResponse(); return }
		
		//report success to client
		client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
		client?.urlProtocol(self, didLoad: contentString.data(using: String.Encoding.utf8)!)
		client?.urlProtocolDidFinishLoading(self)
	}
	
	override open func stopLoading() {
	}

	//convience wrapper for sending an error message to the client
	fileprivate func reportBadResponse() {
		client?.urlProtocol(self, didFailWithError: NSError(domain: NSURLErrorDomain, code: NSURLErrorBadServerResponse, userInfo: [NSURLErrorFailingURLStringErrorKey:request.url!]))
	}
	
	///splits raw data into headers and content
	///
	/// - parameter data: raw data to split
	/// - returns: a tuple of the header and content strings
	fileprivate func splitResponseData(_ data:Data) -> (String,String)? {
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
	func extractHeaders(_ headerString:String) -> (Int,String,[String:String])? {
		let responseRegex = try! NSRegularExpression(pattern: "^(HTTP/1.\\d) (\\d+)", options: [.anchorsMatchLines])
		guard let matchResult = responseRegex.firstMatch(in: headerString, options: [], range: headerString.toNSRange) , matchResult.numberOfRanges == 3,
			let statusRange = matchResult.rangeAt(2).toStringRange(headerString),
			let versionRange = matchResult.rangeAt(1).toStringRange(headerString)
			else { reportBadResponse(); return nil }
		guard let statusCode = Int(headerString.substring(with:statusRange)) else { reportBadResponse(); return nil }
		let versionString = headerString.substring(with:versionRange)
		let headersString = headerString.substring(from:statusRange.upperBound)
		var headers = [String:String]()
		let headerRegex = try! NSRegularExpression(pattern: "(.+): (.*)", options: [])
		headerRegex.enumerateMatches(in: headersString, options: [], range: NSMakeRange(0, headersString.characters.count))
		{ (matchResult, _, _) in
			if let key = matchResult?.string(index:1, forString: headersString), let value = matchResult?.string(index:2, forString: headersString)
			{
				headers[key] = value
			}
		}
		return (statusCode, versionString, headers)
	}
}
