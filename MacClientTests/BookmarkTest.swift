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
		let original = Bookmark(name: "test", host: "rc2.io", port: 8080, user: "tuser", project: "proj", workspace: "wspace", secure:true)
		let odict = try! original.serialize()
		let ostr = odict.rawString()
		XCTAssertNotNil(ostr)
		let ndict = JSON.parse(ostr!)
		let newver = Bookmark(json: ndict)
		XCTAssertEqual(original, newver)
	}
}
