//
//  HelpControllerTests.swift
//  SwiftClient
//
//  Created by Mark Lilback on 4/21/16.
//  Copyright © 2016 Rc2. All rights reserved.
//

import XCTest
@testable import MacClient

class HelpControllerTests: XCTestCase {
	
	func testSearch() {
		// This is an example of a functional test case.
		// Use XCTAssert and related functions to verify your tests produce the correct results.
		let help = HelpController()
		XCTAssertTrue(help.topicsStartingWith("print").count >= 1)
		XCTAssertTrue(help.topicsStartingWith("XDFGsdfgsdf").count == 0)
	}
}
