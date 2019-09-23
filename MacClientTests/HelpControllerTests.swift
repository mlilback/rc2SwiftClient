//
//  HelpControllerTests.swift
//  Rc2Client
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import XCTest
@testable import ClientCore

class HelpControllerTests: XCTestCase {
	
	func testSearch() {
		// This is an example of a functional test case.
		// Use XCTAssert and related functions to verify your tests produce the correct results.
		let help = HelpController()
		XCTAssertTrue(help.searchTitles("print").count >= 1)
		XCTAssertTrue(help.searchTitles("XDFGsdfgsdf").count == 0)
	}
}
