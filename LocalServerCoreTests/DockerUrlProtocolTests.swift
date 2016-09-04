//
//  DockerUrlProtocolTests.swift
//  SwiftClient
//
//  Created by Mark Lilback on 7/8/16.
//  Copyright © 2016 Rc2. All rights reserved.
//

import XCTest
@testable import LocalServerCore
import SwiftyJSON
import Darwin

class DockerUrlProtocolTests: XCTestCase {
	var sessionConfig: NSURLSessionConfiguration?
	var session: NSURLSession?
	
	override class func setUp() {
//		let envname = "CFNETWORK_DIAGNOSTICS".dataUsingEncoding(NSUTF8StringEncoding)
//		let value = "3".dataUsingEncoding(NSUTF8StringEncoding)
//		Darwin.setenv(UnsafePointer(envname!.bytes), UnsafePointer(value!.bytes), 1)
	}
	
	override func setUp() {
		super.setUp()
		sessionConfig = NSURLSessionConfiguration.defaultSessionConfiguration()
		sessionConfig?.protocolClasses = [DockerUrlProtocol.self]
		session = NSURLSession(configuration: sessionConfig!)
	}
	
	override func tearDown() {
		super.tearDown()
	}

	func testVersionRequest() {
		let expect = expectationWithDescription("version")
		let url = NSURL(string: "unix:///version")!
		var fetchedData:NSData?
		let task = session?.dataTaskWithRequest(NSURLRequest(URL: url)) { data, response, error in
			fetchedData = data
			guard let httpResponse = response as? NSHTTPURLResponse else { XCTFail(); return }
			XCTAssertNotNil(httpResponse)
			XCTAssertEqual(httpResponse.statusCode, 200)
			expect.fulfill()
		}
		task?.resume()
		self.waitForExpectationsWithTimeout(2) { (err) -> Void in }
		let json = JSON.parse(String(data:fetchedData!, encoding: NSUTF8StringEncoding)!)
		XCTAssertNotNil(json.dictionary)
		XCTAssertNotNil(json["Version"].string)
		XCTAssertNotNil(json["KernelVersion"].string)
	}

}
