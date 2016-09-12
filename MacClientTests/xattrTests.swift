//
//  xattrTests.swift
//  SwiftClient
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import XCTest
@testable import MacClient

class xattrTests: BaseTest {
	var fileUrl: URL!
	let contentString = "foo\nbar\nbaz"
	let testAttr1Name = "io.rc2.XAttrTest.attr1"
	
	override func setUp() {
		super.setUp()
		fileUrl = URL(string: UUID().uuidString, relativeTo: mockFM.tempDirUrl as URL)!.absoluteURL
		try? contentString.data(using: String.Encoding.utf8)?.write(to: fileUrl, options: [])
	}
	
	override func tearDown() {
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
