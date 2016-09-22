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
	var defaults: UserDefaults!
	
	override func setUp() {
		super.setUp()
		URLSessionConfiguration.mockingjaySwizzleDefaultSessionConfiguration()
		defaults = UserDefaults(suiteName: UUID().uuidString)! //not sure why this is failable
	}
	
	override func tearDown() {
		super.tearDown()
	}

	func testDockerInstalled() {
		let docker = DockerManager(userDefaults:defaults)
		XCTAssertTrue(docker.isInstalled)
	}

	func testVersionCommand() {
		let expect = self.expectation(description: "file download")
		let docker = DockerManager(userDefaults:defaults)
		let future = docker.initializeConnection()
		var error:NSError?
		future.onSuccess { _ in
			expect.fulfill()
		}.onFailure { err in
			error = err
			expect.fulfill()
		}
		self.waitForExpectations(timeout: 2) { _ in
			XCTAssertNil(error)
			XCTAssertGreaterThan(docker.apiVersion, 1.2)
		}
	}
	
	func testDockerNotLoaded() {
		let expect = expectation(description: "failed to load")
		let docker = DockerManager(hostUrl: "http://foobar:9899/", baseInfoUrl: "http://localhost:12351/", userDefaults:defaults)
		var failed = false
		docker.initializeConnection().onSuccess { _ in
			expect.fulfill()
		}.onFailure { _ in
			failed = true
			expect.fulfill()
		}
		waitForExpectations(timeout: 2) { _ in
			XCTAssertTrue(failed)
		}
	}
	
	func testLoadRequiredInfo() {
		//initialize using fake docker info
		stubGetRequest(uriPath: "/version", fileName: "version")
		stubGetRequest(uriPath: "/imageInfo.json", fileName: "imageInfo")

		let docker = DockerManager()
		let expect = expectation(description: "load required info")
		let future = docker.checkForImageUpdate()
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
	
	///uses Mockingjay to stub out a request for uriPath with the contents of fileName.json
	func stubGetRequest(uriPath:String, fileName:String) {
		let path : String = Bundle(for: DockerManagerTests.self).path(forResource: fileName, ofType: "json")!
		let resultData = try? Data(contentsOf: URL(fileURLWithPath: path))
		stub(http(method: .get, uri: uriPath), builder: jsonData(resultData!))
	}
}
