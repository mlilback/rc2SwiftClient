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
	let user = "me@rc2"
	var keychain: Keychain?
	
	override func setUp() {
		super.setUp()
		keychain = Keychain()
	}
	
	override func tearDown() {
		try! keychain!.setString(user, value: nil)
		super.tearDown()
	}

	func testAddDeleteItems() {
		let pass = "monkeysoup"
		do {
			try keychain!.setString(user, value:pass)
		} catch let error as NSError {
			XCTFail("got error \(error)")
		}
		let retrievedPass = keychain!.getString(user)
		XCTAssertEqual(retrievedPass, pass)
		let pass2 = "soupmonkey"
		do {
			try keychain!.setString(user, value: pass2)
		} catch let error as NSError {
			XCTFail("gpt errpr \(error)")
		}
		let retrievedPass2 = keychain!.getString(user)
		XCTAssertEqual(retrievedPass2, pass2)
		keychain!.removeKey(user)
		XCTAssertNil(keychain!.getString(user))
	}

}
