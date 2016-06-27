//
//  xattrTests.swift
//  SwiftClient
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import XCTest
@testable import MacClient

class xattrTests: BaseTest {
	var fileUrl: NSURL!
	let contentString = "foo\nbar\nbaz"
	let testAttr1Name = "io.rc2.XAttrTest.attr1"
	
	override func setUp() {
		super.setUp()
		fileUrl = NSURL(string: NSUUID().UUIDString, relativeToURL: mockFM.tempDirUrl)!.absoluteURL
		contentString.dataUsingEncoding(NSUTF8StringEncoding)?.writeToURL(fileUrl, atomically: false)
	}
	
	override func tearDown() {
		super.tearDown()
	}

	func testXAttrs() {
		let attrValue = "foo".dataUsingEncoding(NSUTF8StringEncoding)!
		var getRsp = dataForXAttributeNamed(testAttr1Name, atURL:fileUrl)
		XCTAssertNil(getRsp.data)
		attrValue.writeToURL(fileUrl, atomically: false)
		let setRsp = setXAttributeWithName(testAttr1Name, data: attrValue, atURL: fileUrl)
		XCTAssertNil(setRsp)
		getRsp = dataForXAttributeNamed(testAttr1Name, atURL: fileUrl)
		XCTAssertEqual(getRsp.data, attrValue)
		removeXAttributeNamed(testAttr1Name, atURL: fileUrl)
		getRsp = dataForXAttributeNamed(testAttr1Name, atURL: fileUrl)
		XCTAssertNil(getRsp.data)
	}
}
