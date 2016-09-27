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
import Result

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
		stubGetRequest(uriPath: "https://www.rc2.io/imageInfo.json", fileName: "imageInfo")
		
		//swizzle wasn't working for some reason, so we manually add the mockingjay protocol to session config
		let sessionConfig = URLSessionConfiguration.default
		sessionConfig.protocolClasses = [MockingjayProtocol.self, DockerUrlProtocol.self] as [AnyClass] + sessionConfig.protocolClasses!
		let docker = DockerManager(userDefaults:defaults, sessionConfiguration:sessionConfig)
		let expect = expectation(description: "load required info")
		var result: Result<Bool, NSError>?
		docker.initializeConnection().flatMap { _ in
			docker.checkForImageUpdate()
		}.onComplete { r2 in
			result = r2
			expect.fulfill()
		}
		waitForExpectations(timeout: 20) { _ in
			//checkForImageUpdate() bool result does not mean success, means that was loaded remotely. so just check on if there was an error or not
			if let _ = result?.error {
				XCTFail()
			}
			XCTAssertEqual(docker.imageInfo?.version, 1)
			XCTAssertEqual(docker.imageInfo?.dbserver.name, "dbserver")
		}
	}
	
	func testNetworkExists() {
		stubGetRequest(uriPath: "/networks", fileName: "networks")
		let docker = DockerManager()
		let expect = expectation(description: "load networks")
		var result = false
		docker.initializeConnection().flatMap { _ in
			docker.networkExists(named:"rc2server")
		}.onComplete { r2 in
			if case .success(let s) = r2 { result = s }
			expect.fulfill()
		}
		waitForExpectations(timeout: 1) { _ in
			XCTAssertTrue(result)
		}
	}
	
	///uses Mockingjay to stub out a request for uriPath with the contents of fileName.json
	func stubGetRequest(uriPath:String, fileName:String) {
		let path : String = Bundle(for: DockerManagerTests.self).path(forResource: fileName, ofType: "json")!
		let resultData = try? Data(contentsOf: URL(fileURLWithPath: path))
		stub(uri(uri: uriPath), builder: jsonData(resultData!))
	}
}
