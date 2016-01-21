//
//  ColorEnumTests.swift
//  Rc2Client
//
//  Created by Mark Lilback on 1/14/16.
//  Copyright © 2016 West Virginia University. All rights reserved.
//

import XCTest
@testable import MacClient

class ColorEnumTests: XCTestCase {
	func testOutputColors() {
		let defurl = NSBundle(forClass: Session.self).URLForResource("CommonDefaults", withExtension: "plist")
		let cdict = NSDictionary(contentsOfURL: defurl!)?.objectForKey("OutputColors") as! Dictionary<String,String>
		OutputColors.allValues.forEach({
			XCTAssertNotNil(try! Color(hex:(cdict[$0.rawValue])!))
		})
	}

	func testSyntaxColors() {
		let defurl = NSBundle(forClass: Session.self).URLForResource("CommonDefaults", withExtension: "plist")
		let cdict = NSDictionary(contentsOfURL: defurl!)?.objectForKey("SyntaxColors") as! Dictionary<String,String>
		SyntaxColors.allValues.forEach({
			XCTAssertNotNil(try! Color(hex:(cdict[$0.rawValue])!))
		})
	}
}
