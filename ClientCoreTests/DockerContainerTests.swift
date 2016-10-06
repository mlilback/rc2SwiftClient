//
//  DockerContainerTests.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import XCTest
@testable import ClientCore

class DockerContainerTests: XCTestCase {

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
	
}

