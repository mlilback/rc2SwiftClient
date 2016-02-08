//
//  FileCacheTests.swift
//  SwiftClient
//
//  Created by Mark Lilback on 2/8/16.
//  Copyright © 2016 Rc2. All rights reserved.
//

import XCTest
@testable import MacClient

class FileCacheTests: BaseTest {
	var cache:FileCache!

	override func setUp() {
		super.setUp()
		cache = FileCache()
	}
	
	override func tearDown() {
		super.tearDown()
	}
	
	func testExample() {
		let file = (sessionData.workspaces.first?.files.first)!
		XCTAssert(!cache.isFileCached(file))
	}

}
