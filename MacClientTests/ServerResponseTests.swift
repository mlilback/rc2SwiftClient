//
//  ServerResponseTests.swift
//  Rc2Client
//
//  Created by Mark Lilback on 1/13/16.
//  Copyright © 2016 West Virginia University. All rights reserved.
//

import XCTest
@testable import MacClient
import SwiftyJSON

class ServerResponseTests: XCTestCase {

	override func setUp() {
		super.setUp()
	}
	
	override func tearDown() {
		super.tearDown()
	}

	func testListVariables() {
		let path : String = NSBundle(forClass: self.dynamicType).pathForResource("listvars", ofType: "json")!
		let resultData = NSData(contentsOfFile: path)
		let srcJson = JSON(data:resultData!)
		let rsp = ServerResponse.parseResponse(srcJson)
		XCTAssertNotNil(rsp)
		switch (rsp!) {
		case .Variables(_, let delta, let single, let variables):
			XCTAssert(!delta)
			XCTAssert(!single)
			XCTAssertEqual(variables.count, 5)
			XCTAssertEqual(variables[0].name, "str")
			XCTAssertEqual(variables[0].primitiveType, PrimitiveType.String)
			XCTAssertEqual(variables[0].stringValueAtIndex(0), "foo")
			XCTAssertEqual(variables[1].name, "logic")
			XCTAssertEqual(variables[1].primitiveType, PrimitiveType.Boolean)
			XCTAssertEqual(variables[1].boolValueAtIndex(1), false)
			XCTAssertEqual(variables[2].name, "doubleVal")
			XCTAssertEqual(variables[2].primitiveType, PrimitiveType.Double)
			XCTAssertEqual(variables[2].doubleValueAtIndex(0), 12)
			XCTAssertEqual(variables[3].name, "intVal")
			XCTAssertEqual(variables[3].primitiveType, PrimitiveType.Integer)
			XCTAssertEqual(variables[3].doubleValueAtIndex(2), 4)
			XCTAssertEqual(variables[4].name, "speciald")
			XCTAssertEqual(variables[4].primitiveType, PrimitiveType.Double)
			XCTAssertEqual(variables[4].doubleValueAtIndex(0), (kCFNumberNaN as NSNumber))
			XCTAssertEqual(variables[4].doubleValueAtIndex(1), (kCFNumberPositiveInfinity as NSNumber))
			XCTAssertEqual(variables[4].doubleValueAtIndex(2), (kCFNumberNegativeInfinity as NSNumber))
			XCTAssertEqual(variables[4].doubleValueAtIndex(3), 3.14)
		default:
			XCTFail("incorrect parseResponse type")
		}
	}
	
	func testSessionImageFromJSON() {
		let path : String = NSBundle(forClass: self.dynamicType).pathForResource("resultsWithImages", ofType: "json")!
		let resultData = NSData(contentsOfFile: path)
		let srcJson = JSON(data:resultData!)
		let rsp = ServerResponse.parseResponse(srcJson)
		XCTAssertNotNil(rsp)
		switch (rsp!) {
			case .ExecComplete(let qid, let bid, let imgs):
				XCTAssertEqual(imgs.count, 3)
				XCTAssertEqual(bid, 1)
				XCTAssertEqual(qid, 1001)
				sessionImageCodingTest(imgs[0])
			default:
				XCTFail("parseResponse returned wrong ServerResponse type")
		}
	}
	
	func sessionImageCodingTest(image:SessionImage) {
		let data = NSKeyedArchiver.archivedDataWithRootObject(image)
		let obj = NSKeyedUnarchiver.unarchiveObjectWithData(data) as! SessionImage
		XCTAssertEqual(image, obj)
	}
}
