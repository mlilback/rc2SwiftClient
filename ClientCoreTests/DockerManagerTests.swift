//
//  DockerManagerTests.swift
//  SwiftClient
//
//  Created by Mark Lilback on 7/6/16.
//  Copyright © 2016 Rc2. All rights reserved.
//

import XCTest
@testable import ClientCore
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

//	func testDockerNotInstalled() {
//		let docker = DockerManager(path: "/usr/local/foo/bar")
//		XCTAssertFalse(docker.isInstalled)
//	}
	
	func testVersionCommand() {
		let expect = self.expectation(description: "file download")
		let docker = DockerManager()
		let future = docker.dockerRequest("/version")
		future.onSuccess { json in
			XCTAssert(Double(json["ApiVersion"].stringValue)! > 1.2)
			expect.fulfill()
		}.onFailure {_ in 
			XCTFail()
			expect.fulfill()
		}
		self.waitForExpectations(timeout: 2) { (err) -> Void in }
	}
	
	func testLoadImages() {
		//make sure running
		let expect = self.expectation(description:"check docker running")
		let docker = DockerManager()
		var success = false
		docker.isDockerRunning() { rspSuccess in
			success = rspSuccess
			expect.fulfill()
		}
		self.waitForExpectations(timeout:20) { (err) -> Void in
			XCTAssertTrue(success)
		}
		let imgExpect = self.expectation(description: "load image info")
		let future = docker.loadImages()
		success = false
		var images:[DockerImage]?
		var error:NSError?
		future.onSuccess { rspImages in
			success = true
			images = rspImages
			imgExpect.fulfill()
		}.onFailure { err in
			error = err
			imgExpect.fulfill()
		}
		self.waitForExpectations(timeout:20) { (err) -> Void in
			XCTAssertTrue(success)
			XCTAssertEqual(images?.count, 1)
			print(images?.first?.tags)
			if let anErr = error {
				print("error fetching image info: \(anErr)")
			}
		}
	}
}
