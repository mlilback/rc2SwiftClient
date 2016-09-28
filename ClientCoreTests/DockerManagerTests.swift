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
	var sessionConfig:URLSessionConfiguration!
	
	override func setUp() {
		super.setUp()
		sessionConfig = URLSessionConfiguration.default
		sessionConfig.protocolClasses = [MockingjayProtocol.self, DockerUrlProtocol.self] as [AnyClass] + sessionConfig.protocolClasses!
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
		
		let docker = DockerManager(userDefaults:defaults, sessionConfiguration:sessionConfig)
		guard let result = callDockerMethod(docker:docker, action: { docker in
			return docker.checkForImageUpdate()
		}) else {
			XCTFail("failed to create network")
			return
		}
		//checkForImageUpdate() result does not mean success, means that was loaded remotely. so just check on if there was an error or not
		XCTAssertNil(result.error)
		XCTAssertEqual(docker.imageInfo?.version, 1)
		XCTAssertEqual(docker.imageInfo?.dbserver.name, "dbserver")
	}
	
	func testNetworkExists() {
		stubGetRequest(uriPath: "/networks", fileName: "networks")
		guard let result = callDockerMethod(docker:nil, action: { docker in
			return docker.networkExists(named:"rc2server")
		}) else {
			XCTFail("failed to create network")
			return
		}
		XCTAssertTrue(result.value ?? false)
	}
	
	func testCreateNetwork() {
		stub(uri(uri:"/networks/create"), builder: http(201))
		guard let result = callDockerMethod(docker:nil, action: { docker in
			return docker.createNetwork(named:"foo")
		}) else {
			XCTFail("failed to create network")
			return
		}
		XCTAssertTrue(result.value ?? false)
	}
	
	func testCreateNetworkFailure() {
		stub(uri(uri:"/networks/create"), builder: http(500))
		guard let result = callDockerMethod(docker:nil, action: { docker in
			return docker.createNetwork(named:"foo")
		}) else {
			XCTFail("failed to create network")
			return
		}
		XCTAssertNotNil(result.error)
	}

	/// helper function to create a network. caller should have stubbed the uri "/networks/create"
	func callDockerMethod(docker:DockerManager?, action: @escaping (DockerManager) -> Future<Bool,NSError>) -> Result<Bool, NSError>?
	{
		var dm:DockerManager? = docker
		if dm == nil {
			dm = DockerManager(userDefaults:defaults, sessionConfiguration:sessionConfig)
		}
		let expect = expectation(description: "create network")
		var result: Result<Bool, NSError>?
		dm!.initializeConnection().flatMap { r1 in
			action(dm!)
		}.onComplete { r2 in
			result = r2
			expect.fulfill()
		}
		waitForExpectations(timeout: 2) { _ in }
		return result
	}

	///uses Mockingjay to stub out a request for uriPath with the contents of fileName.json
	func stubGetRequest(uriPath:String, fileName:String) {
		let path : String = Bundle(for: DockerManagerTests.self).path(forResource: fileName, ofType: "json")!
		let resultData = try? Data(contentsOf: URL(fileURLWithPath: path))
		stub(uri(uri: uriPath), builder: jsonData(resultData!))
	}
}
