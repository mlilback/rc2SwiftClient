//
//  ColorEnumTests.swift
//  SwiftClient
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import XCTest
@testable import MacClient

class ColorEnumTests: XCTestCase {
	func testOutputColors() {
		let defurl = NSBundle(forClass: Session.self).URLForResource("CommonDefaults", withExtension: "plist")
		let cdict = NSDictionary(contentsOfURL: defurl!)?.objectForKey("OutputColors") as! Dictionary<String,String>
		OutputColors.allValues.forEach({
			XCTAssertNotNil(try! PlatformColor(hex:(cdict[$0.rawValue])!))
		})
	}

	func testSyntaxColors() {
		let defurl = NSBundle(forClass: Session.self).URLForResource("CommonDefaults", withExtension: "plist")
		let cdict = NSDictionary(contentsOfURL: defurl!)?.objectForKey("SyntaxColors") as! Dictionary<String,String>
		SyntaxColors.allValues.forEach({
			XCTAssertNotNil(try! PlatformColor(hex:(cdict[$0.rawValue])!))
		})
	}
}
