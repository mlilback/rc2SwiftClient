//
//  KeychainTests.swift
//  SwiftClient
//
//  Created by Mark Lilback on 1/17/16.
//  Copyright © 2016 Rc2. All rights reserved.
//

import XCTest
@testable import MacClient

class KeychainTests: XCTestCase {
	var keychain: Keychain?
	
	override func setUp() {
		super.setUp()
		keychain = Keychain()
	}
	
	override func tearDown() {
		//kechain.removeAll()
		super.tearDown()
	}

	func testAddDeleteItems() {
		let pass = "monkeysoup"
		let user = "me@rc2"
		do {
			try keychain!.setString(user, value:pass)
		} catch let error as NSError {
			XCTFail("got error \(error)")
		}
		let retrievedPass = keychain!.getString(user)
		XCTAssertEqual(retrievedPass, pass)
		keychain!.removeKey(user)
		XCTAssertNil(keychain!.getString(user))
	}

}
