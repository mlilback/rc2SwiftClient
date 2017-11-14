//
//  xattrTests.swift
//  Rc2Client
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import XCTest
@testable import Networking

class xattrTests: XCTestCase {
	var fileUrl: URL!
	let contentString = "foo\nbar\nbaz"
	let testAttr1Name = "io.rc2.XAttrTest.attr1"
	var tmpUrl: URL!
	
	override func setUp() {
		super.setUp()
		tmpUrl = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try? FileManager.default.createDirectory(at: tmpUrl, withIntermediateDirectories: true, attributes: nil)
		fileUrl = URL(string: UUID().uuidString, relativeTo: tmpUrl)!.absoluteURL
		try? contentString.data(using: String.Encoding.utf8)?.write(to: fileUrl, options: [])
	}
	
	override func tearDown() {
		try? FileManager.default.removeItem(at: tmpUrl)
		super.tearDown()
	}

	func testXAttrs() {
		let attrValue = "foo".data(using: String.Encoding.utf8)!
		var getRsp = dataForXAttributeNamed(testAttr1Name, atURL:fileUrl)
		XCTAssertNil(getRsp.data)
		try? attrValue.write(to: fileUrl, options: [])
		let setRsp = setXAttributeWithName(testAttr1Name, data: attrValue, atURL: fileUrl)
		XCTAssertNil(setRsp)
		getRsp = dataForXAttributeNamed(testAttr1Name, atURL: fileUrl)
		XCTAssertEqual(getRsp.data, attrValue)
		removeXAttributeNamed(testAttr1Name, atURL: fileUrl)
		getRsp = dataForXAttributeNamed(testAttr1Name, atURL: fileUrl)
		XCTAssertNil(getRsp.data)
	}
}
