//
//  ToolbarValidationTests.swift
//  SwiftClient
//
//  Created by Mark Lilback on 1/20/16.
//  Copyright © 2016 Rc2. All rights reserved.
//

import XCTest
@testable import MacClient

class ToolbarValidationTests: XCTestCase {

	func testValidation() {
		let titem = NSToolbarItem(itemIdentifier: "foo")
		titem.tag = 0
		titem.validateClosure = { (item) -> Void in
			XCTAssertEqual(item.tag, 0)
			item.tag = 1
		}
		titem.validate()
		XCTAssertEqual(titem.tag, 1)
	}

}
