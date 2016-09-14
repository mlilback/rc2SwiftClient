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
@testable import MacClient

class DockerUrlProtocolTests: XCTestCase {
	var sessionConfig: URLSessionConfiguration?
	var session: URLSession?
	
	override class func setUp() {
//		let envname = "CFNETWORK_DIAGNOSTICS".dataUsingEncoding(NSUTF8StringEncoding)
//		let value = "3".dataUsingEncoding(NSUTF8StringEncoding)
//		Darwin.setenv(UnsafePointer(envname!.bytes), UnsafePointer(value!.bytes), 1)
	}
	
	override func setUp() {
		super.setUp()
		continueAfterFailure = false
		sessionConfig = URLSessionConfiguration.default
		sessionConfig?.protocolClasses = [DockerUrlProtocol.self]
		session = URLSession(configuration: sessionConfig!)
	}
	
	override func tearDown() {
		super.tearDown()
	}

	func testVersionRequest() {
		let expect = expectation(description: "contact docker daemon")
		let url = URL(string: "unix:///version")!
		var fetchedData:Data?
		var httpResponse:HTTPURLResponse?
		var error:NSError?
		let task = session?.dataTask(with: URLRequest(url: url), completionHandler: { data, response, err in
			error = err as NSError?
			httpResponse = response as? HTTPURLResponse
			fetchedData = data
			expect.fulfill()
		}) 
		task?.resume()
		self.waitForExpectations(timeout: 2) { (err) -> Void in
			XCTAssertNil(error)
			XCTAssertNotNil(httpResponse)
			XCTAssertEqual(httpResponse!.statusCode, 200)
			XCTAssertNotNil(fetchedData)
			let jsonStr = String(data:fetchedData!, encoding: String.Encoding.utf8)!
			let json = JSON.parse(jsonStr)
		XCTAssertNotNil(json.dictionary)
			let verStr = json["ApiVersion"].string
			XCTAssertNotNil(verStr)
			guard let verNum = Double(verStr!) else { XCTFail("failed to parse version number"); return }
			XCTAssertNotNil(verNum >= 1.24)
		}
	}

}
