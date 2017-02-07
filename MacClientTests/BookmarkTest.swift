//
//  BookmarkTest.swift
//  SwiftClient
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import XCTest
import Freddy
@testable import MacClient
import Networking

class BookmarkTest: XCTestCase {
	
	func testBookmarkSerialization() {
		let server = ServerHost(name: "festus", host:"festus.rc2.io", port: 8088, user: "test", secure: false)
		let original = Bookmark(name: "test", server: server, project: "proj", workspace: "wspace")
		let ostr = try! original.toJSON() .serializeString()
		XCTAssertNotNil(ostr)
		let ndict = try! JSON(jsonString: ostr)
		let newver = try! Bookmark(json: ndict)
		XCTAssertEqual(original, newver)
	}
}
