//
//  MonoFontManagerTests.swift
//  Rc2Client
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import XCTest
@testable import MacClient

class MonoFontManagerTests: XCTestCase {

	func testFontManager() {
		let fm = MonoFontManager()
		XCTAssertEqual(fm.displayNameForFont("Menlo-Regular")!, "Menlo")
	}
}
