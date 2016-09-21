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
import BrightFutures
import Mockingjay

class DockerManagerTests: XCTestCase {
	
	override func setUp() {
		super.setUp()
		URLSessionConfiguration.mockingjaySwizzleDefaultSessionConfiguration()
	}
	
	override func tearDown() {
		super.tearDown()
	}

	func testDockerInstalled() {
		let docker = DockerManager()
		XCTAssertTrue(docker.isInstalled)
	}

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
	
	func testLoadRequiredInfo() {
		let docker = DockerManager()
		initializeManager(docker: docker)

		stubGetRequest(uriPath: "/imageInfo.json", fileName: "imageInfo")
		let expect = expectation(description: "load required info")
		let future = docker.loadRequiredImageInfo()
		var loaded:Bool = false
		var error:NSError? = nil
		future.onSuccess { success in
			loaded = success
			expect.fulfill()
		}.onFailure { err in
			error = err
			expect.fulfill()
		}
		waitForExpectations(timeout: 2) { _ in
			XCTAssertTrue(loaded)
			XCTAssertNil(error)
			XCTAssertEqual(docker.imageInfo?.version, 1)
			XCTAssertEqual(docker.imageInfo?.dbserver.name, "dbserver")
		}
	}
	
	///initializes docker with fake data from version.json
	func initializeManager(docker:DockerManager) {
		let expect = expectation(description: "docker init")
		stubGetRequest(uriPath: "/version", fileName: "version")
		var running:Bool = false
		docker.isDockerRunning() { isRun in
			running = isRun
			expect.fulfill()
		}
		waitForExpectations(timeout: 1, handler:nil)
		XCTAssertTrue(running)
	}
	
	///uses Mockingjay to stub out a request for uriPath with the contents of fileName.json
	func stubGetRequest(uriPath:String, fileName:String) {
		let path : String = Bundle(for: DockerManagerTests.self).path(forResource: fileName, ofType: "json")!
		let resultData = try? Data(contentsOf: URL(fileURLWithPath: path))
		stub(http(method: .get, uri: uriPath), builder: jsonData(resultData!))
	}
}
