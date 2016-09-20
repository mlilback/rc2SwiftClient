//
//  TestDataProtocolTests.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import XCTest

class TestDataProtocolTests: XCTestCase, URLSessionDataDelegate {
	var expect:XCTestExpectation?
	var receivedData:[Data] = []
	var receivedResponse:HTTPURLResponse?
	
	override func setUp() {
		super.setUp()
		expect = expectation(description: "test request")
		receivedData.removeAll()
	}
	
	func testBasic() {
		let config = URLSessionConfiguration.default
		config.protocolClasses = [TestDataProtocol.self]
		let session = URLSession(configuration: config, delegate:self, delegateQueue:OperationQueue.main)
		var req = URLRequest(url: URL(string: "test://me.com/test")!)
		req.httpMethod = "GET"
		let task = session.dataTask(with: req)
		
		let data1 = "{\"msg\":\"foo\", \"count\": 1 }".data(using: .utf8)!
		let data2 = "{\"msg\":\"bar\", \"count\": 2 }".data(using: .utf8)!
		let data3 = "{\"msg\":\"baz\", \"count\": 3 }".data(using: .utf8)!
		let data = [data1, data2, data3]
		
		TestDataProtocol.responseHeaders = ["Content-type" : "application/json"]
		TestDataProtocol.responseData = data
		
		task.resume()
		waitForExpectations(timeout: 2) { (err) in
			guard err == nil else { XCTFail() ; return }
			XCTAssertNotNil(self.receivedResponse)
			XCTAssertEqual(self.receivedResponse!.allHeaderFields["Content-Type"] as! String, "application/json")
			XCTAssertEqual(self.receivedData.count, 3)
			XCTAssertEqual(self.receivedData[0], data1)
			XCTAssertEqual(self.receivedData[1], data2)
			XCTAssertEqual(self.receivedData[2], data3)
		}
	}
	
	func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void)
	{
		receivedResponse = response as? HTTPURLResponse
		completionHandler(.allow)
	}
	
	func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
		receivedData.append(data)
	}
	
	func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		expect?.fulfill()
	}
}
