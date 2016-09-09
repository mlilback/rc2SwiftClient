//
//  BookmarkTest.swift
//  SwiftClient
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import XCTest
import SwiftyJSON
@testable import MacClient

class BookmarkTest: XCTestCase {
	
	func testBookmarkSerialization() {
		let server = ServerHost(name: "festus", host:"festus.rc2.io", port: 8088, user: "test", secure: false)
		let original = Bookmark(name: "test", server: server, project: "proj", workspace: "wspace")
		let odict = try! original.toJson()
		let ostr = odict.rawString()
		XCTAssertNotNil(ostr)
		let ndict = JSON.parse(ostr!)
		let newver = Bookmark(json: ndict)
		XCTAssertEqual(original, newver)
	}
}
