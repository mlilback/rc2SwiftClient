//
//  DockerUrlProtocolTests.swift
//  SwiftClient
//
//  Created by Mark Lilback on 7/8/16.
//  Copyright © 2016 Rc2. All rights reserved.
//

import XCTest
@testable import MacClient
import SwiftyJSON
import Darwin

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
		sessionConfig = URLSessionConfiguration.default
		sessionConfig?.protocolClasses = [DockerUrlProtocol.self]
		session = URLSession(configuration: sessionConfig!)
	}
	
	override func tearDown() {
		super.tearDown()
	}

	func testVersionRequest() {
		let expect = expectation(description: "version")
		let url = URL(string: "unix:///version")!
		var fetchedData:Data?
		let task = session?.dataTask(with: URLRequest(url: url), completionHandler: { data, response, error in
			fetchedData = data
			guard let httpResponse = response as? HTTPURLResponse else { XCTFail(); return }
			XCTAssertNotNil(httpResponse)
			XCTAssertEqual(httpResponse.statusCode, 200)
			expect.fulfill()
		}) 
		task?.resume()
		self.waitForExpectations(timeout: 2) { (err) -> Void in }
		let json = JSON.parse(String(data:fetchedData!, encoding: String.Encoding.utf8)!)
		XCTAssertNotNil(json.dictionary)
		XCTAssertNotNil(json["Version"].string)
		XCTAssertNotNil(json["Experimental"].bool)
	}

}
