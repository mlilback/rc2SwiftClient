//
//  DockerUrlProtocol.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Darwin

open class DockerUrlProtocol: URLProtocol, URLSessionDelegate {
	fileprivate let socketPath = "/var/run/docker.sock"
	
	override open class func canInit(with request:URLRequest) -> Bool {
		return request.url!.scheme == "unix"
	}
	
	open override class func canonicalRequest(for request:URLRequest) -> URLRequest {
		return request
	}
	
	override open func startLoading() {
		let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
		guard fd >= 0 else {
			client?.urlProtocol(self, didFailWithError: NSError(domain: NSPOSIXErrorDomain, code: Int(Darwin.errno), userInfo: nil))
			return
		}
		let pathlen = socketPath.utf8CString.count
		precondition(pathlen < 104) //size limit of sockaddr_un.sun_path
		var addr = Darwin.sockaddr_un()
		addr.sun_family = sa_family_t(AF_UNIX)
		addr.sun_len = UInt8(pathlen)
		_ = withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
			strncpy(UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self), socketPath, pathlen)
		}
		var code:Int32 = 0
		withUnsafePointer(to: &addr) { ptr in
			ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { ar in
				code = connect(fd, ar, socklen_t(MemoryLayout<sockaddr_un>.size))
			}
		}
		guard code >= 0 else { reportBadResponse(); return }
		let fh = FileHandle(fileDescriptor: fd)
		guard let path = request.url?.path else { reportBadResponse(); return }
		let outStr = "GET \(path) HTTP/1.0\r\n\r\n"
		fh.write(outStr.data(using: String.Encoding.utf8)!)
		let inData = fh.readDataToEndOfFile()
		
		guard let (headersString, contentString) = splitResponseData(inData) else { reportBadResponse(); return }
		guard let (statusCode, httpVersion, headers) = extractHeaders(headersString) else { reportBadResponse(); return }
		guard let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: httpVersion, headerFields: headers) else { reportBadResponse(); return }

		client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
		client?.urlProtocol(self, didLoad: contentString.data(using: String.Encoding.utf8)!)
		client?.urlProtocolDidFinishLoading(self)
	}
	
	override open func stopLoading() {
	}

	fileprivate func reportBadResponse() {
		client?.urlProtocol(self, didFailWithError: NSError(domain: NSURLErrorDomain, code: NSURLErrorBadServerResponse, userInfo: [NSURLErrorFailingURLStringErrorKey:request.url!]))
	}
	
	fileprivate func splitResponseData(_ data:Data) -> (String,String)? {
		guard let responseString = String(data:data, encoding: String.Encoding.utf8),
			let endFirstLineRange = responseString.range(of: "\r\n\r\n")
			else { reportBadResponse(); return nil }
		let headersString = responseString.substring(with: responseString.startIndex..<endFirstLineRange.lowerBound)
		let contentString = responseString.substring(from: endFirstLineRange.upperBound)
		return (headersString, contentString)
	}
	
	func extractHeaders(_ headerString:String) -> (Int,String,[String:String])? {
		let responseRegex = try! NSRegularExpression(pattern: "^(HTTP/1.\\d) (\\d+)", options: [.anchorsMatchLines])
		guard let matchResult = responseRegex.firstMatch(in: headerString, options: [], range: headerString.toNSRange) , matchResult.numberOfRanges == 3,
			let statusRange = matchResult.rangeAt(2).toStringRange(headerString),
			let versionRange = matchResult.rangeAt(1).toStringRange(headerString)
			else { reportBadResponse(); return nil }
		guard let statusCode = Int(headerString.substring(with: statusRange)) else { reportBadResponse(); return nil }
		let versionString = headerString.substring(with: versionRange)
		let headersString = headerString.substring(from: statusRange.upperBound)
		var headers = [String:String]()
		let headerRegex = try! NSRegularExpression(pattern: "(.+): (.*)", options: [])
		headerRegex.enumerateMatches(in: headersString, options: [], range: NSMakeRange(0, headersString.characters.count))
		{ (matchResult, _, _) in
			if let key = matchResult?.stringAtIndex(1, forString: headersString), let value = matchResult?.stringAtIndex(2, forString: headersString)
			{
				headers[key] = value
			}
		}
		return (statusCode, versionString, headers)
	}
}
