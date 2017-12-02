//
//  TestDataProtocol.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Darwin

///TestDataProtocol is a subclass of NSURLProtocol for returning data for testing purposes

open class TestDataProtocol: URLProtocol, URLSessionDelegate {
	///statically set before make a request with this protocol. Obviously, only 1 request can be processed at a time, which should be fine for a unit test
	static var responseData:[Data] = [Data(base64Encoded: "YQ==")!]
	static var responseHeaders:[String:String] = [:]
	
	override open class func canInit(with request:URLRequest) -> Bool {
		return request.url!.scheme == "test"
	}
	
	open override class func canonicalRequest(for request:URLRequest) -> URLRequest {
		return request
	}
	
	override open func startLoading() {
		//split the response into headers and content, create a response object
		guard let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "1.1", headerFields: TestDataProtocol.responseHeaders) else { reportBadResponse(); return }
		
		//return data to client. We need to do this via closures with a staggered display, otherwise
		// the system will coalesce all the datas into 1 chunk
		client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
		var delay:Double = 0
		for (index, aData) in TestDataProtocol.responseData.enumerated() {
			delay = Double(index) * 0.01
			DispatchQueue.main.asyncAfter(deadline: // swiftlint:disable_this fallthrough.now() + delay) {
				self.client?.urlProtocol(self, didLoad: aData)
			}
		}
		DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.1) {
			self.client?.urlProtocolDidFinishLoading(self)
		}
	}
	
	override open func stopLoading() {
	}
	
	//convience wrapper for sending an error message to the client
	fileprivate func reportBadResponse() {
		client?.urlProtocol(self, didFailWithError: NSError(domain: NSURLErrorDomain, code: NSURLErrorBadServerResponse, userInfo: [NSURLErrorFailingURLStringErrorKey:request.url!]))
	}
	
}
