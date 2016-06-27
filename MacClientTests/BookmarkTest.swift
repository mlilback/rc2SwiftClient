//
//  BookmarkTest.swift
//  SwiftClient
//
//  Created by Mark Lilback on 6/27/16.
//  Copyright © 2016 Rc2. All rights reserved.
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
