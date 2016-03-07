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
	
	func testFloats() {
		let fileUrl = NSBundle(forClass: self.dynamicType).URLForResource("float", withExtension: "mpdata", subdirectory: "testFiles")!
		let data = NSData(contentsOfURL: fileUrl)
		let packer = MessagePackParser(data: data!)
		let rootVals = try! packer.parse()
		if case .ArrayValue(let vals) = rootVals[0] {
			if case .FloatValue(let fval) = vals[0] { XCTAssertEqual(fval, Float(1.1)) } else { XCTFail("float != 1.1") }
			if case .DoubleValue(let dval) = vals[1] { XCTAssertEqual(dval, Double(22323.123456789)) } else { XCTFail("double != 22323.123456789") }
		} else {
			XCTFail("failed to parse float arary")
		}
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

	func testArrays() {
		let fileUrl = NSBundle(forClass: self.dynamicType).URLForResource("smarray", withExtension: "mpdata", subdirectory: "testFiles")!
		let data = NSData(contentsOfURL: fileUrl)
		let packer = MessagePackParser(data: data!)
		let rootVals = try! packer.parse()
		XCTAssertEqual(rootVals.count, 1)
		guard case .ArrayValue(let a1) = rootVals[0] else {
			XCTFail("failed to get root array")
			return
		}
		evaluateArray(a1, index:0, count: 5)
		evaluateArray(a1, index:1, count: 25)
		evaluateArray(a1, index:2, count: Int(Int16.max) + 1)
	}

	func evaluateArray(arrayVal:[MessageValue], index:Int, count:Int) {
		guard case .ArrayValue(let array) = arrayVal[index] else {
			XCTFail("failed to evaluate array of len \(count)")
			return
		}
		XCTAssertEqual(count, array.count)
		if case .IntValue(let i1) = array[count - 1] {
			XCTAssertEqual(count - 1, i1)
		} else {
			XCTFail("invalid value for array value \(count)")
		}
	}
	
	func testDictionary() {
		let fileUrl = NSBundle(forClass: self.dynamicType).URLForResource("dict", withExtension: "mpdata", subdirectory: "testFiles")!
		let data = NSData(contentsOfURL: fileUrl)
		let packer = MessagePackParser(data: data!)
		let rootVals = try! packer.parse()
		guard case .DictionaryValue(let dict) = rootVals[0]  else {
			XCTFail("failed to parse dict")
			return
		}
		XCTAssertEqual(2, dict.count)
		guard case .FloatValue(let fval) = dict["key1"]! else {
			XCTFail("failed to parse key1 from dict")
			return
		}
		XCTAssertEqual(Float(1.1), fval)
		guard case .BooleanValue(let bval) = dict["enabled"]! else {
			XCTFail("failed to parse enabled from dict")
			return
		}
		XCTAssertEqual(true, bval)
	}
	
	func testStrings() {
		let fileUrl = NSBundle(forClass: self.dynamicType).URLForResource("string", withExtension: "mpdata", subdirectory: "testFiles")!
		let data = NSData(contentsOfURL: fileUrl)
		let packer = MessagePackParser(data: data!)
		let rootVals = try! packer.parse()
		if case .ArrayValue(let vals) = rootVals[0] {
			if case .StringValue(let sstr) = vals[0] {
				XCTAssertEqual(sstr.utf8.count, 100)
				XCTAssert(sstr.hasSuffix("ZZ"), "end of string 0 incorrect")
			} else {
				XCTFail("first string incorrect")
			}
			if case .StringValue(let lstr) = vals[1] {
				let imax = Int(Int16.max) + 1
				XCTAssertEqual(lstr.utf8.count, imax, "lstr len wrong: \(lstr.utf8.count) vs \(imax)")
				XCTAssert(lstr.hasSuffix("ZZ"), "end of string 1 incorrect")
			} else {
				XCTFail("second string incorrect")
			}
		} else {
			XCTFail("failed to parse array for integers")
		}
	}

}
