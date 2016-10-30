//
//  DockerUrlProtocolTests.swift
//  SwiftClient
//
//  Created by Mark Lilback on 7/8/16.
//  Copyright © 2016 Rc2. All rights reserved.
//

import XCTest
import SwiftyJSON
import Darwin
import Nimble
@testable import ClientCore

class DockerUrlProtocolTests: XCTestCase, URLSessionDataDelegate {
	var sessionConfig: URLSessionConfiguration?
	var session: URLSession?
	var semaphore: DispatchSemaphore?
	var xpect: XCTestExpectation?
	var queue: OperationQueue = OperationQueue()
	
	override func setUp() {
		super.setUp()
		queue.underlyingQueue = DispatchQueue.global(qos: .userInitiated)
		continueAfterFailure = false
		sessionConfig = URLSessionConfiguration.default
		sessionConfig?.protocolClasses = [TestDockerProtocol.self] as [AnyClass]
		session = URLSession(configuration: sessionConfig!, delegate: self, delegateQueue: queue)
		semaphore = DispatchSemaphore(value: 0)
		xpect = expectation(description: "bg url")
	}
	
	override func tearDown() {
		super.tearDown()
	}

	func testChunkedResponse() {

		let url = URL(string: "unix:///events")!
		let request = NSMutableURLRequest(url: url)
		request.rc2_chunkedResponse = true
		let task = session?.dataTask(with: request as URLRequest)
		task?.resume()
		//semaphore?.wait()
		waitForExpectations(timeout: 10) { (error) in
			expect(error).to(beNil())
		}
	}
	
//	func testVersionRequest() {
//		let expect = expectation(description: "contact docker daemon")
//		let url = URL(string: "unix:///version")!
//		var fetchedData:Data?
//		var httpResponse:HTTPURLResponse?
//		var error:NSError?
//		let task = session?.dataTask(with: URLRequest(url: url), completionHandler: { data, response, err in
//			error = err as NSError?
//			httpResponse = response as? HTTPURLResponse
//			fetchedData = data
//			expect.fulfill()
//		}) 
//		task?.resume()
//		self.waitForExpectations(timeout: 2) { (err) -> Void in
//			XCTAssertNil(error)
//			XCTAssertNotNil(httpResponse)
//			XCTAssertEqual(httpResponse!.statusCode, 200)
//			XCTAssertNotNil(fetchedData)
//			let jsonStr = String(data:fetchedData!, encoding: String.Encoding.utf8)!
//			let json = JSON.parse(jsonStr)
//		XCTAssertNotNil(json.dictionary)
//			let verStr = json["ApiVersion"].string
//			XCTAssertNotNil(verStr)
//			guard let verNum = Double(verStr!) else { XCTFail("failed to parse version number"); return }
//			XCTAssertNotNil(verNum >= 1.24)
//		}
//	}
//
	open func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void)
	{
		completionHandler(Foundation.URLSession.ResponseDisposition.allow)
	}
	
	open func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
		let str = String(data: data, encoding:String.Encoding.utf8)!
		print("got \(str)")
		xpect?.fulfill()
	}
	
	open func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		print("did complete")
	}

}

public class TestDockerProtocol: DockerUrlProtocol {
	override func writeRequestData(data: Data, fileHandle: FileHandle) {
	}
}

