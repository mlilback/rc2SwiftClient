//
//  MultipartInputStreamTest.swift
//  Rc2Client
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import XCTest
@testable import MacClient

// swiftlint:disable all

class MultipartInputStreamTest: XCTestCase {
	var fileUrl:NSURL!
	var fileContents:NSData!

	override func setUp() {
		super.setUp()
		fileUrl = NSBundle(forClass: RestServerTest.self).URLForResource("lognormal", withExtension: "R")!
		fileContents = NSData(contentsOfURL: fileUrl)!
	}
	
	override func tearDown() {
		super.tearDown()
	}

	func testStream() {
		let stream = MultipartInputStream(URL: fileUrl)
		defer { stream!.close() }
		let bufferSize = 1024
		var buffer = [UInt8](count:bufferSize, repeatedValue:0)
		let streamData = NSMutableData(capacity: bufferSize)
		stream!.appendStringPart("foo", value:"bar")
		stream!.prepareForRead()
		stream!.open()
		if stream!.hasBytesAvailable { print("got it") }
		while (stream!.hasBytesAvailable) {
			let len = stream!.read(&buffer, maxLength:buffer.count)
			if len > 0 {
				streamData?.appendBytes(buffer, length: len)
			}
		}
		let multiString = String(data: streamData!, encoding: NSUTF8StringEncoding)!
		let parts = (multiString as NSString).componentsSeparatedByString("--\(stream!.boundary)\r\n")
		XCTAssertEqual(parts.count, 4) //first and last are empty because source starts and ends with boundary
		XCTAssertEqual(parts[1], "Content-Disposition: form-data; name=\"foo\"\r\n\r\nbar\r\n")
		XCTAssert(parts[2].hasPrefix("Content-Disposition: form-data; name=\"lognormal.R\"\r\nContent-Type: application/octet-stream\r\n\r\n"))
	}
}
