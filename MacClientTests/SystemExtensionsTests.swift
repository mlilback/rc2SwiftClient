//
//  SystemExtensionsTests.swift
//  SwiftClient
//
//  Created by Mark Lilback on 3/22/16.
//  Copyright © 2016 Rc2. All rights reserved.
//

import XCTest
import MacClient

class SystemExtensionsTests: XCTestCase {
	func testPlatformColor() {
		let red = try! PlatformColor(hex:"FF0000")
		XCTAssertEqual(Int(red.redComponent * 255.0), 255)
		XCTAssertEqual(Int(red.greenComponent * 255.0), 0)
		XCTAssertEqual(Int(red.blueComponent * 255.0), 0)
		let gray = try! PlatformColor(hex:"999999")
		XCTAssertEqual(Int(gray.redComponent * 255.0), 153)
		XCTAssertEqual(Int(gray.greenComponent * 255.0), 153)
		XCTAssertEqual(Int(gray.blueComponent * 255.0), 153)
	}
}
