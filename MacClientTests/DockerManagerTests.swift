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
		let docker = DockerManager()
		do {
			let json = try docker.dockerRequest("version")
			XCTAssert(Double(json["ApiVersion"].stringValue)! > 1.2)
		} catch let err as NSError {
			XCTFail("execption while getting version: \(err)")
		}
	}

	fileprivate func sockaddr_cast(_ p: UnsafePointer<sockaddr_un>) -> UnsafePointer<sockaddr> {
		return UnsafePointer<sockaddr>(p)
	}
}
