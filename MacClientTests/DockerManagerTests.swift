//
//  DockerManagerTests.swift
//  SwiftClient
//
//  Created by Mark Lilback on 7/6/16.
//  Copyright © 2016 Rc2. All rights reserved.
//

import XCTest
@testable import MacClient
import SwiftyJSON

class DockerManagerTests: XCTestCase {
	
	override func setUp() {
		super.setUp()
	}
	
	override func tearDown() {
		super.tearDown()
	}

	func testDockerInstalled() {
		let docker = DockerManager()
		XCTAssertTrue(docker.isInstalled)
	}

	func testDockerNotInstalled() {
		let docker = DockerManager(path: "/usr/local/foo/bar")
		XCTAssertFalse(docker.isInstalled)
	}
	
	func testVersionCommand() {
		let expect = self.expectation(description: "file download")
		let docker = DockerManager()
		let future = try docker.dockerRequest("/version")
		future.onSuccess { json in
			XCTAssert(Double(json["ApiVersion"].stringValue)! > 1.2)
			expect.fulfill()
		}.onFailure {_ in 
			XCTFail()
			expect.fulfill()
		}
		self.waitForExpectations(timeout: 2) { (err) -> Void in }
	}
}
