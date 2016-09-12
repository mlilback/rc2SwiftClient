//
//  SystemExtensionsTests.swift
//  SwiftClient
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
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
	
	func testNSRange() {
		let str = "string"
		let nsrng = NSRange(0, str.length)
		let strRng = nsrng.toStringRange(str)
		XCTAssertEqual(str.characters[strRng.start], "s")
		XCTFail() //implement this and more
	}
}
