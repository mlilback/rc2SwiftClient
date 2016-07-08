//
//  DockerUrlProtocol.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

public class DockerUrlProtocol: NSURLProtocol, NSURLSessionDelegate {
	private let socketPath = "/var/run/docker.sock"
	
	override public class func canInitWithRequest(request:NSURLRequest) -> Bool {
		return request.URL!.scheme == "unix"
	}
	
	public override class func canonicalRequestForRequest(request:NSURLRequest) -> NSURLRequest {
		return request
	}
	
	override public func startLoading() {
		let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
		guard fd >= 0 else {
			client?.URLProtocol(self, didFailWithError: NSError(domain: NSPOSIXErrorDomain, code: Int(Darwin.errno), userInfo: nil))
			return
		}
		var addr = Darwin.sockaddr_un()
		addr.sun_family = UInt8(AF_LOCAL)
		addr.sun_len = UInt8(sizeof(sockaddr_un))
		socketPath.withCString { cpath in
			withUnsafeMutablePointer(&addr.sun_path) { spath in
				strcpy(UnsafeMutablePointer(spath), cpath)
			}
		}
		let code = Darwin.connect(fd, sockaddr_cast(&addr), socklen_t(strideof(sockaddr_un)))
		guard code >= 0 else { reportBadResponse(); return }
		let fh = NSFileHandle(fileDescriptor: fd)
		guard let path = request.URL?.path else { reportBadResponse(); return }
		let outStr = "GET \(path) HTTP/1.0\r\n\r\n"
		fh.writeData(outStr.dataUsingEncoding(NSUTF8StringEncoding)!)
		let inData = fh.readDataToEndOfFile()
		
		guard let (headersString, contentString) = splitResponseData(inData) else { reportBadResponse(); return }
		guard let (statusCode, httpVersion, headers) = extractHeaders(headersString) else { reportBadResponse(); return }
		guard let response = NSHTTPURLResponse(URL: request.URL!, statusCode: statusCode, HTTPVersion: httpVersion, headerFields: headers) else { reportBadResponse(); return }

		client?.URLProtocol(self, didReceiveResponse: response, cacheStoragePolicy: .NotAllowed)
		client?.URLProtocol(self, didLoadData: contentString.dataUsingEncoding(NSUTF8StringEncoding)!)
		client?.URLProtocolDidFinishLoading(self)
	}
	
	override public func stopLoading() {
	}

	private func reportBadResponse() {
		client?.URLProtocol(self, didFailWithError: NSError(domain: NSURLErrorDomain, code: NSURLErrorBadServerResponse, userInfo: [NSURLErrorFailingURLStringErrorKey:request.URL!]))
	}
	
	private func splitResponseData(data:NSData) -> (String,String)? {
		guard let responseString = String(data:data, encoding: NSUTF8StringEncoding),
			let endFirstLineRange = responseString.rangeOfString("\r\n\r\n")
			else { reportBadResponse(); return nil }
		let headersString = responseString.substringWithRange(responseString.startIndex..<endFirstLineRange.startIndex)
		let contentString = responseString.substringFromIndex(endFirstLineRange.endIndex)
		return (headersString, contentString)
	}
	
	func extractHeaders(headerString:String) -> (Int,String,[String:String])? {
		let responseRegex = try! NSRegularExpression(pattern: "^(HTTP/1.\\d) (\\d+)", options: [.AnchorsMatchLines])
		guard let matchResult = responseRegex.firstMatchInString(headerString, options: [], range: headerString.toNSRange) where matchResult.numberOfRanges == 3,
			let statusRange = matchResult.rangeAtIndex(2).toStringRange(headerString),
			let versionRange = matchResult.rangeAtIndex(1).toStringRange(headerString)
			else { reportBadResponse(); return nil }
		guard let statusCode = Int(headerString.substringWithRange(statusRange)) else { reportBadResponse(); return nil }
		let versionString = headerString.substringWithRange(versionRange)
		let headersString = headerString.substringFromIndex(statusRange.endIndex)
		var headers = [String:String]()
		let headerRegex = try! NSRegularExpression(pattern: "(.+): (.*)", options: [])
		headerRegex.enumerateMatchesInString(headersString, options: [], range: NSMakeRange(0, headersString.characters.count))
		{ (matchResult, _, _) in
			if let key = matchResult?.stringAtIndex(1, forString: headersString), let value = matchResult?.stringAtIndex(2, forString: headersString)
			{
				headers[key] = value
			}
		}
		return (statusCode, versionString, headers)
	}
	
	private func sockaddr_cast(p: UnsafePointer<sockaddr_un>) -> UnsafePointer<sockaddr> {
		return UnsafePointer<sockaddr>(p)
	}
}
