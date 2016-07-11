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
		let expect = expectationWithDescription("test version")
		let docker = DockerManager()
		docker.dockerRequest("/version").onSuccess { json in
			expect.fulfill()
			XCTAssert(Double(json["ApiVersion"].stringValue)! > 1.2)
		}
		waitForExpectationsWithTimeout(2, handler: nil)
	}

	private func sockaddr_cast(p: UnsafePointer<sockaddr_un>) -> UnsafePointer<sockaddr> {
		return UnsafePointer<sockaddr>(p)
	}
}
