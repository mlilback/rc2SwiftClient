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

class DockerManagerTests: BaseDockerTest {
	
	func testDockerInstalled() {
		let docker = DockerManager(userDefaults:userDefaults)
		XCTAssertTrue(docker.isInstalled)
	}

	func testVersionCommand() {
		stubGetRequest(uriPath: "/version", fileName: "version")
		stubGetRequest(uriPath: "/containers/json", fileName: "containers")
		let expect = self.expectation(description: "file download")
		let docker = DockerManager(userDefaults:userDefaults)
		let future = docker.initializeConnection()
		var error:NSError?
		future.onSuccess { _ in
			expect.fulfill()
		}.onFailure { err in
			error = err
			expect.fulfill()
		}
		self.waitForExpectations(timeout: 200) { _ in
			XCTAssertNil(error)
			XCTAssertGreaterThan(docker.apiVersion, 1.2)
		}
	}
	
	func testDockerNotLoaded() {
		let expect = expectation(description: "failed to load")
		let docker = DockerManager(hostUrl: "http://foobar:9899/", baseInfoUrl: "http://localhost:12351/", userDefaults:userDefaults)
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
		
		let docker = DockerManager(userDefaults:userDefaults, sessionConfiguration:sessionConfig)
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

	func testContainerRefresh() {
		stubGetRequest(uriPath: "/containers/json", fileName: "containers")
		let docker = DockerManager(userDefaults:userDefaults, sessionConfiguration:sessionConfig)
		let result = callDockerMethod(docker: docker, action: { docker in
			return docker.refreshContainers()
		})
		guard let _ = result?.value else {
			XCTFail("failed to refresh containers")
			return
		}
		XCTAssertTrue(docker.containers[.dbserver]?.imageName == "rc2server/dbserver")
	}
}
