//
//  MessagePackParserTests.swift
//  SwiftClient
//
//  Created by Mark Lilback on 3/5/16.
//  Copyright © 2016 Rc2. All rights reserved.
//

import XCTest
@testable import MacClient

class MessagePackParserTests: XCTestCase {

	override func setUp() {
		super.setUp()
	}
	
	override func tearDown() {
		super.tearDown()
	}

	func testFixedString() {
		//last byte is aflag to test returned offset is correct
		let bytes:[UInt8] = [ 0xA8, 0x70, 0x72, 0x6F, 0x70, 0x4E, 0x61, 0x6D, 0x65, 0xBE ]
		let packer = MessagePackParser(bytes: bytes)
		XCTAssertEqual(bytes, packer.bytes)
		let results = packer.parseFixedString()
		XCTAssertEqual(results, "propName")
		XCTAssertEqual(0xBE, bytes[packer.curIndex])
	}
	
	func testFixedInt() {
		let bytes:[UInt8] = [ 0x23, 0xf5 ] // 35, 21
		let packer = MessagePackParser(bytes: bytes)
		let presult = packer.parseFixedPositiveInt()
		XCTAssertEqual(35, presult)
		let nresult = packer.parseFixedNegativeInt()
		XCTAssertEqual(-21, nresult)
	}
	
	func testParseNil() {
	 	let bytes:[UInt8] = [ 0xc0 ]
		let packer = MessagePackParser(bytes: bytes)
		let result = packer.parseNil()
		XCTAssert(result)
	}
	
	func testBooleanAndNil() {
		let fileUrl = NSBundle(forClass: self.dynamicType).URLForResource("boolnil", withExtension: "mpdata", subdirectory: "testFiles")!
		let data = NSData(contentsOfURL: fileUrl)
		let packer = MessagePackParser(data: data!)
		let rootVals = try! packer.parse()
		if case .ArrayValue(let vals) = rootVals[0] {
			XCTAssert(vals[0] == MessageValue.NilValue)
			XCTAssert(vals[1] == MessageValue.BooleanValue(true))
			XCTAssert(vals[2] == MessageValue.BooleanValue(false))
		} else {
			XCTFail("failed to parse array for bool & nil")
		}
	}
	
	func testIntegers() {
		let fileUrl = NSBundle(forClass: self.dynamicType).URLForResource("ints", withExtension: "mpdata", subdirectory: "testFiles")!
		let data = NSData(contentsOfURL: fileUrl)
		let packer = MessagePackParser(data: data!)
		let rootVals = try! packer.parse()
		if case .ArrayValue(let vals) = rootVals[0] {
			if case .IntValue(let ival) = vals[0] { XCTAssertEqual(ival, Int(-111)) } else { XCTFail("first int not != -111:") }
			if case .IntValue(let ival) = vals[1] { XCTAssertEqual(ival, Int(1435)) } else { XCTFail("second int not != 1435:") }
			if case .UIntValue(let ival) = vals[2] { XCTAssertEqual(ival, UInt(123352345234)) } else { XCTFail("third int not != 123352345234:") }
		} else {
			XCTFail("failed to parse array for integers")
		}
	}
}
