//
//  ServerResponseTests.swift
//  SwiftClient
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
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
		let path : String = Bundle(for: type(of: self)).path(forResource: "listvars", ofType: "json")!
		let resultData = try? Data(contentsOf: URL(fileURLWithPath: path))
		let srcJson = JSON(data:resultData!)
		let rsp = ServerResponse.parseResponse(srcJson)
		XCTAssertNotNil(rsp)
		switch (rsp!) {
		case .variables(let single, let variables):
			XCTAssert(!single)
			XCTAssertEqual(variables.count, 10)
			var aVar = variables.filter() { $0.name == "str" }.first!
			XCTAssertEqual(aVar.primitiveType, PrimitiveType.String)
			XCTAssertEqual(aVar.stringValueAtIndex(0), "foo")
			XCTAssertEqual(aVar.description, "[\"foo\", \"bar\"]")
			aVar = variables.filter() { $0.name == "logic" }.first!
			XCTAssertEqual(aVar.primitiveType, PrimitiveType.Boolean)
			XCTAssertEqual(aVar.boolValueAtIndex(1), false)
			aVar = variables.filter() { $0.name == "doubleVal" }.first!
			XCTAssertEqual(aVar.name, "doubleVal")
			XCTAssertEqual(aVar.primitiveType, PrimitiveType.Double)
			XCTAssertEqual(aVar.doubleValueAtIndex(0), 12)
			aVar = variables.filter() { $0.name == "intVal" }.first!
			XCTAssertEqual(aVar.name, "intVal")
			XCTAssertEqual(aVar.primitiveType, PrimitiveType.Integer)
			XCTAssertEqual(aVar.doubleValueAtIndex(2), 4)
			aVar = variables.filter() { $0.name == "speciald" }.first!
			XCTAssertEqual(aVar.name, "speciald")
			XCTAssertEqual(aVar.primitiveType, PrimitiveType.Double)
			XCTAssertEqual(aVar.doubleValueAtIndex(0), Double.nan)
			XCTAssertEqual(aVar.doubleValueAtIndex(1), Double.infinity)
			XCTAssertEqual(aVar.doubleValueAtIndex(2), -Double.infinity)
			XCTAssertEqual(aVar.doubleValueAtIndex(3), 3.14)
			aVar = variables.filter() { $0.name == "dct" }.first!
			XCTAssertEqual(aVar.name, "dct")
			XCTAssertEqual(aVar.type, VariableType.dateTime)
			aVar = variables.filter() { $0.name == "f" }.first!
			XCTAssertEqual(aVar.name, "f")
			XCTAssertEqual(aVar.type, VariableType.factor)
			XCTAssertEqual(aVar.levels!, ["a","b","c","d","e"])
			aVar = variables.filter() { $0.name == "cpx" }.first!
			XCTAssertEqual(aVar.name, "cpx")
			XCTAssertEqual(aVar.primitiveType, PrimitiveType.Complex)
			XCTAssertEqual(aVar.stringValueAtIndex(0), "0.09899058348162+1.28356775897029i")
			aVar = variables.filter() { $0.name == "r1" }.first!
			XCTAssertEqual(aVar.name, "r1")
			XCTAssertEqual(aVar.primitiveType, PrimitiveType.Raw)
			XCTAssertEqual(aVar.length, 4)
			aVar = variables.filter() { $0.name == "nn" }.first!
			XCTAssertEqual(aVar.name, "nn")
			XCTAssertEqual(aVar.primitiveType, PrimitiveType.Null)
			XCTAssertEqual(aVar.length, 0)
		default:
			XCTFail("incorrect parseResponse type")
		}
	}
	
	func testSessionImageFromJSON() {
		let path : String = Bundle(for: type(of: self)).path(forResource: "resultsWithImages", ofType: "json")!
		let resultData = try? Data(contentsOf: URL(fileURLWithPath: path))
		let srcJson = JSON(data:resultData!)
		let rsp = ServerResponse.parseResponse(srcJson)
		XCTAssertNotNil(rsp)
		switch (rsp!) {
			case .execComplete(let qid, let bid, let imgs):
				XCTAssertEqual(imgs.count, 3)
				XCTAssertEqual(bid, 1)
				XCTAssertEqual(qid, 1001)
				sessionImageCodingTest(imgs[0])
			default:
				XCTFail("parseResponse returned wrong ServerResponse type")
		}
	}
	
	func sessionImageCodingTest(_ image:SessionImage) {
		let data = NSKeyedArchiver.archivedData(withRootObject:image)
		let obj = NSKeyedUnarchiver.unarchiveObject(with: data) as! SessionImage
		XCTAssertEqual(image, obj)
	}
}
