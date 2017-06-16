//
//  SystemExtensionsTests.swift
//  SwiftClient
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import XCTest
import MacClient
import ClientCore

class SystemExtensionsTests: XCTestCase {
	func testPlatformColor() {
		guard let red = PlatformColor(hexString:"FF0000") else {
			XCTFail(); return
		}
		XCTAssertEqual(Int(red.redComponent * 255.0), 255)
		XCTAssertEqual(Int(red.greenComponent * 255.0), 0)
		XCTAssertEqual(Int(red.blueComponent * 255.0), 0)
		guard let gray = PlatformColor(hexString:"999999") else {
			XCTFail(); return
		}
		XCTAssertEqual(Int(gray.redComponent * 255.0), 153)
		XCTAssertEqual(Int(gray.greenComponent * 255.0), 153)
		XCTAssertEqual(Int(gray.blueComponent * 255.0), 153)
	}
	
	func testNSRange() {
		let str = "string"
		let nsrng = NSRange(location: 0, length: str.characters.count)
		let strRng = nsrng.toStringRange(str)
		XCTAssertEqual(str.characters[(strRng?.lowerBound)!], "s")
		//TODO: fully test this extension
	}
}
