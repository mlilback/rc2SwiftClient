//
//  DockerContainerTests.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import XCTest
@testable import ClientCore

class DockerContainerTests: BaseDockerTest {

	func testContainerTypeParsing() {
		let t1 = ContainerType.from(imageName:"rc2server/dbserver")
		XCTAssertEqual(t1, .dbserver)
		let t2 = ContainerType.from(imageName:"rc2server/dbserver:0.4")
		XCTAssertEqual(t2, .dbserver)
		let t3 = ContainerType.from(imageName:"rc2server/appserver")
		XCTAssertEqual(t3, .appserver)
		let t4 = ContainerType.from(imageName:"rc2server/compute:latest")
		XCTAssertEqual(t4, .compute)
		let t5 = ContainerType.from(imageName: "foo/bar:latest")
		XCTAssertNil(t5)
	}
	
	func testContainerRefresh() {
		stubGetRequest(uriPath: "/containers/json", fileName: "containers")
		let api = DockerAPIImplementation(baseUrl: URL(string:"http://10.0.1.9:2375/")!, sessionConfig: sessionConfig)
		api.refreshContainers().startWithResult { result in
			
		}
//		let docker = DockerManager(userDefaults:userDefaults, sessionConfiguration:sessionConfig)
//		let result = callDockerMethod(docker: docker, action: { docker in
//			return docker.refreshContainers()
//		})
//		guard let _ = result?.value else {
//			XCTFail("failed to refresh containers")
//			return
//		}
//		XCTAssertTrue(docker.containers[.dbserver]?.imageName == "rc2server/dbserver")
	}
}

