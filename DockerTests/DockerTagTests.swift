//
//  DockerTagTests.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import XCTest
@testable import Docker

class DockerTagTests: XCTestCase {
	
	func testName() {
		let tag = DockerTag(tag: "busybox")
		XCTAssertNotNil(tag)
		XCTAssertNil(tag!.repo)
		XCTAssertNil(tag!.version)
		XCTAssertEqual(tag!.name, "busybox")
	}
	
	func testRepoName() {
		let tag = DockerTag(tag: "box/busybox")
		XCTAssertNotNil(tag)
		XCTAssertEqual(tag!.repo, "box")
		XCTAssertNil(tag!.version)
		XCTAssertEqual(tag!.name, "busybox")
	}

	func testRepoNameVersion() {
		let tag = DockerTag(tag: "box/busybox:latest")
		XCTAssertNotNil(tag)
		XCTAssertEqual(tag!.repo, "box")
		XCTAssertEqual(tag!.version, "latest")
		XCTAssertEqual(tag!.name, "busybox")
	}

	func testNameVersion() {
		let tag = DockerTag(tag: "busybox:latest")
		XCTAssertNotNil(tag)
		XCTAssertNil(tag!.repo)
		XCTAssertEqual(tag!.version, "latest")
		XCTAssertEqual(tag!.name, "busybox")
	}
}
