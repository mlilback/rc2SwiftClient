//
//  ColorEnumTests.swift
//  SwiftClient
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import XCTest
@testable import MacClient
import ClientCore

class ColorEnumTests: XCTestCase {
	func testOutputColors() {
		let defurl = Bundle(for: Session.self).url(forResource: "CommonDefaults", withExtension: "plist")
		let cdict = NSDictionary(contentsOf: defurl!)?.object(forKey: "OutputColors") as! Dictionary<String,String>
		OutputColors.allValues.forEach({
			XCTAssertNotNil(try! PlatformColor(hex:(cdict[$0.rawValue])!))
		})
	}

	func testSyntaxColors() {
		let defurl = Bundle(for: Session.self).url(forResource: "CommonDefaults", withExtension: "plist")
		let cdict = NSDictionary(contentsOf: defurl!)?.object(forKey: "SyntaxColors") as! Dictionary<String,String>
		SyntaxColors.allValues.forEach({
			XCTAssertNotNil(try! PlatformColor(hex:(cdict[$0.rawValue])!))
		})
	}
}
