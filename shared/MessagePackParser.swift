//
//  MessagePackParser.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import CoreFoundation

enum MessagePackError: Int, ErrorType {
	case InvalidBinaryData
	case UnsupportedDictionaryKey
	case NoMoreData
}

enum Formats:Int {
	case PositiveFixInt = 0
}

enum MessageValue: Equatable {
	case NilValue
	case BooleanValue(Bool)
	///on 64-bit platforms, this is returned for all int/uint values except 64 bit uints which are returned as UInt
	///on 32-bit platforms, this is returned for 8/16/32 bit ints, and 8/16 bit uints
	case IntValue(Int)
	///on 32-bit platforms, this is returned for 64-bit ints
	case Int64Value(Int64)
	///on 32-bit platforms, this is returned for 32-bit uints
	case UIntValue(UInt)
	///this is returned for all 64-bit uints
	case UInt64Value(UInt64)
	case StringValue(String)
	case BinaryValue(NSData)
	case ExtValue(NSData)
	case FloatValue(Float)
	case DoubleValue(Double)
	case ArrayValue([MessageValue])
	case DictionaryValue([String:MessageValue])
}

func ==(lhs:MessageValue, rhs:MessageValue) -> Bool {
	switch(lhs, rhs) {
		case (.BooleanValue(let a), .BooleanValue(let b)): return a == b
		case (.NilValue, .NilValue): return true
		case (.IntValue(let a), .IntValue(let b)): return a == b
		case (.Int64Value(let a), .Int64Value(let b)): return a == b
		case (.UIntValue(let a), .UIntValue(let b)): return a == b
		case (.UInt64Value(let a), .UInt64Value(let b)): return a == b
		case (.StringValue(let a), .StringValue(let b)): return a == b
		case (.BinaryValue(let a), .BinaryValue(let b)): return a == b
		case (.FloatValue(let a), .FloatValue(let b)): return a == b
		case (.DoubleValue(let a), .DoubleValue(let b)): return a == b
		//TODO: implement for arrays and dictionaries
		default: return false
	}
}

class MessagePackParser {
	private(set) var bytes:[UInt8]
	private(set) var curIndex:Int = 0
	///returns: true if all the objects have been parsed
	var finishedParsing:Bool {
		return curIndex >= bytes.count - 1
	}
	///returns: nil if parse() has not been called, otherwise array of parsed objects
	var parsedObjects:[MessageValue]?
	
	
	init(bytes:[UInt8]) {
		self.bytes = bytes
	}
	
	init(data:NSData) {
		bytes = [UInt8](count:data.length / sizeof(UInt8), repeatedValue:0)
		data.getBytes(&bytes, length: data.length)
	}
	
	///Parses the next object in the binary data
	func parseNext() throws -> MessageValue {
		guard curIndex < bytes.count else { throw MessagePackError.NoMoreData }
		let byte1 = bytes[curIndex]
		switch(byte1) {
		case 0x0...0x7f as ClosedInterval:
			return .IntValue(parseFixedPositiveInt())
		case 0x90...0x9f as ClosedInterval:
			return .ArrayValue(try parseArray())
		case 0xe0...0xff as ClosedInterval:
			return .IntValue(parseFixedNegativeInt())
		case 0xa0...0xbf as ClosedInterval:
			return .StringValue(parseFixedString())
		case 0xc0:
			curIndex += 1
			return .NilValue
		case 0xc2:
			curIndex += 1
			return .BooleanValue(false)
		case 0xc3:
			curIndex += 1
			return .BooleanValue(true)
		case 0xc4, 0xc5, 0xc6:
			return .BinaryValue(try parseBinary())
		case 0xc7...0xc9, 0xd4...0xd8:
			return .ExtValue(parseExt())
		case 0xca:
			return .FloatValue(parseFloat())
		case 0xcb:
			return .DoubleValue(parseDouble())
		case 0xcc...0xcf as ClosedInterval:
			return try parseUnsignedInt()
		case 0xd0...0xd3 as ClosedInterval:
			return try parseInt()
		case 0xd9...0xdb as ClosedInterval:
			return .StringValue(try parseString())
		case 0xdc, 0xdd:
			return .ArrayValue(try parseArray())
		case 0x80...0x8f, 0xde, 0xdf:
			return .DictionaryValue(try parseMap())
		default:
			throw MessagePackError.InvalidBinaryData
		}
	}
	
	///Parses the binary data and returns an array of the objects decoded
	func parse() throws -> [MessageValue] {
		var objs:[MessageValue] = []
		while (!finishedParsing) {
			objs.append(try parseNext())
		}
		parsedObjects = objs
		return objs
	}
	
	func parseMap() throws -> [String:MessageValue] {
		let byte1 = bytes[curIndex]
		curIndex += 1
		var length = 0
		switch(byte1) {
		case 0x80...0x8f:
			length = Int(byte1) & 0xf
		case 0xde:
			let u16 = bytes.withUnsafeBufferPointer({
				UnsafePointer<UInt16>($0.baseAddress + curIndex).memory
			})
			length = Int(UInt16(bigEndian: u16))
			curIndex += 2
		case 0xdf:
			let u32 = bytes.withUnsafeBufferPointer({
				UnsafePointer<UInt32>($0.baseAddress + curIndex).memory
			})
			length = Int(UInt32(bigEndian: u32))
			curIndex += 4
		default:
			throw MessagePackError.InvalidBinaryData
		}
		//should now read pairs of keys and values
		var dict:[String:MessageValue] = [:]
		for _ in 0..<length {
			let key = try parseNext()
			let value = try parseNext()
			guard case .StringValue(let keyStr) = key else {
				throw MessagePackError.UnsupportedDictionaryKey
			}
			dict[keyStr] = value
		}
		return dict
	}
	
	func parseArray() throws -> [MessageValue] {
		let byte1 = bytes[curIndex]
		curIndex += 1
		var length = 0
		switch(byte1) {
		case 0x90...0x9f as ClosedInterval:
			length = Int(byte1) & 0xf
		case 0xdc:
			let u16 = bytes.withUnsafeBufferPointer({
				UnsafePointer<UInt16>($0.baseAddress + curIndex).memory
			})
			length = Int(UInt16(bigEndian: u16))
			curIndex += 2
		case 0xdd:
			let u32 = bytes.withUnsafeBufferPointer({
				UnsafePointer<UInt32>($0.baseAddress + curIndex).memory
			})
			length = Int(UInt32(bigEndian: u32))
			curIndex += 4
		default:
			throw MessagePackError.InvalidBinaryData
		}
		var objs:[MessageValue] = []
		for _ in 0..<length {
			let mo = try parseNext()
			objs.append(mo)
		}
		return objs
	}
	
	func parseString() throws -> String {
		var length = 0
		let byte1 = bytes[curIndex]
		curIndex += 1
		switch(byte1) {
		case 0xd9:
			length = Int(bytes[curIndex])
			curIndex += 1
		case 0xda:
			let u16 = bytes.withUnsafeBufferPointer({
				UnsafePointer<UInt16>($0.baseAddress + curIndex).memory
			})
			length = Int(UInt16(bigEndian: u16))
			curIndex += 2
		case 0xdb:
			let u32 = bytes.withUnsafeBufferPointer({
				UnsafePointer<UInt32>($0.baseAddress + curIndex).memory
			})
			length = Int(UInt32(bigEndian: u32))
			curIndex += 4
		default:
			throw MessagePackError.InvalidBinaryData
		}
		let str = String(bytes: bytes[curIndex..<curIndex+length], encoding: NSUTF8StringEncoding)
		curIndex += length
		return str!
	}

	func parseDouble() -> Double {
		curIndex += 1
		let dbytes = Array(bytes[curIndex..<curIndex+8])
		var u64:UInt64 = 0
		memcpy(&u64, dbytes, 8)
		let cfswapped = CFSwappedFloat64(v:u64)
		curIndex += 8
		return CFConvertDoubleSwappedToHost(cfswapped)
	}
	
	func parseFloat() -> Float {
		curIndex += 1
		let dbytes = Array(bytes[curIndex..<curIndex+4])
		var u32:UInt32 = 0
		memcpy(&u32, dbytes, 4)
		let cfswapped = CFSwappedFloat32(v:u32)
		curIndex += 4
		return CFConvertFloatSwappedToHost(cfswapped)
	}
	
	func parseExt() -> NSData {
		fatalError("not implemented")
	}
	
	func parseInt() throws -> MessageValue {
		let byte1 = bytes[curIndex]
		curIndex += 1
		var intBytes:[UInt8] = bytes
		switch(byte1) {
		case 0xd0:
			intBytes = bytes[curIndex..<curIndex+1].reverse()
			curIndex += 1
			var i8:Int8 = 0
			memcpy(&i8, intBytes, 1)
			return .IntValue(Int(i8))
		case 0xd1:
			intBytes = bytes[curIndex..<curIndex+2].reverse()
			curIndex += 2
			var i16:Int16 = 0
			memcpy(&i16, intBytes, 2)
			return .IntValue(Int(i16))
		case 0xd2:
			intBytes = bytes[curIndex..<curIndex+4].reverse()
			curIndex += 4
			var i32:Int32 = 0
			memcpy(&i32, intBytes, 4)
			return .IntValue(Int(i32))
		case 0xd3:
			intBytes = bytes[curIndex..<curIndex+8].reverse()
			curIndex += 8
			var i64:Int64 = 0
			memcpy(&i64, intBytes, 8)
			if sizeof(Int) == 8 { return .IntValue(Int(i64)) }
			return .Int64Value(i64)
		default:
			throw MessagePackError.InvalidBinaryData
		}
	}
	
	func parseUnsignedInt() throws -> MessageValue {
		let byte1 = bytes[curIndex]
		var intBytes:[UInt8] = bytes
		curIndex += 1
		switch(byte1) {
		case 0xcc:
			intBytes = bytes[curIndex...curIndex+1].reverse()
			curIndex += 1
			var i8:UInt8 = 0
			memcpy(&i8, intBytes, 1)
			return .IntValue(Int(i8))
		case 0xcd:
			intBytes = bytes[curIndex..<curIndex+2].reverse()
			curIndex += 2
			var i16:UInt16 = 0
			memcpy(&i16, intBytes, 2)
			return .IntValue(Int(i16))
		case 0xce:
			intBytes = bytes[curIndex..<curIndex+4].reverse()
			curIndex += 4
			var i32:UInt32 = 0
			memcpy(&i32, intBytes, 4)
			if sizeof(Int) == 8 { return .IntValue(Int(i32)) }
			return .UIntValue(UInt(i32))
		case 0xcf:
			intBytes = bytes[curIndex..<curIndex+8].reverse()
			curIndex += 8
			var i64:UInt64 = 0
			memcpy(&i64, intBytes, 8)
			if sizeof(Int) == 8 { return .UIntValue(UInt(i64)) }
			return .UInt64Value(i64)
		default:
			throw MessagePackError.InvalidBinaryData
		}
	}
	
	//TODO: write unit test for all three binary types
	func parseBinary() throws -> NSData {
		var size:Int = 0
		switch(bytes[curIndex]) {
		case 0xc4:
			curIndex += 1
			size = Int(bytes[curIndex])
			curIndex += 1
		case 0xc5:
			curIndex += 1
			let u16 = bytes.withUnsafeBufferPointer({
				UnsafePointer<UInt16>($0.baseAddress + curIndex).memory
			})
			size = Int(UInt16(bigEndian: u16))
			curIndex += 2
		case 0xc6:
			curIndex += 1
			let u32 = bytes.withUnsafeBufferPointer({
				UnsafePointer<UInt32>($0.baseAddress + curIndex).memory
			})
			size = Int(UInt32(bigEndian: u32))
			curIndex += 4
		default:
			 throw MessagePackError.InvalidBinaryData
		}
		let data = NSData(bytes:Array(bytes[curIndex...curIndex+size]), length:size)
		curIndex += size
		return data
	}
	
	func parseFixedString() -> String {
		let byte1 = bytes[curIndex]
		let strlen = Int(byte1 & 0x1F)
		let ptr = UnsafeMutablePointer<UInt8>(Array(bytes[curIndex+1...curIndex+strlen]))
		let str = NSString(bytes: ptr, length: strlen, encoding: NSUTF8StringEncoding) as! String
		curIndex += strlen + 1
		return str
	}
	
	func parseFixedPositiveInt() -> Int {
		let byte1 = bytes[curIndex]
		let val = byte1 & 0x7f
		curIndex += 1
		return Int(val)
	}

	func parseFixedNegativeInt() -> Int {
		let byte1 = bytes[curIndex]
		let val = byte1 & 0x1f
		curIndex += 1
		return 0 - Int(val)
	}
	
	func parseNil() -> Bool {
		curIndex += 1
		return bytes[curIndex-1] == 0xc0
	}
}

