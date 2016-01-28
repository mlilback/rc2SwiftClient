//
//  MonoFontManagerTests.swift
//  SwiftClient
//
//  Created by Mark Lilback on 1/28/16.
//  Copyright © 2016 Rc2. All rights reserved.
//

import XCTest
@testable import MacClient

class MonoFontManagerTests: XCTestCase {

	func testFontManager() {
		let fm = MonoFontManager()
		XCTAssertEqual(fm.displayNameForFont("Menlo-Regular")!, "Menlo")
	}
}
