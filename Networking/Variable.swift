//
//  VariableEnums.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Freddy
import ClientCore

/// The possible primitive value types
///
public enum PrimitiveType: String {
	case boolean = "b",
	integer = "i",
	double = "d",
	string = "s",
	complex = "c",
	raw = "r",
	null = "n",
	na = "na" ///never sent from server. used for objects that aren't a primitive
	
	/// returns the PrimitiveType matching the specified typeCode
	///
	/// - Parameter typeCode: the code to parse
	/// - Returns: the matching PrimitiveType value, or .na if not a primitive type
	static func forString(_ typeCode:Swift.String?) -> PrimitiveType {
		guard let code = typeCode else { return .na }
		if let val = PrimitiveType(rawValue: code) { return val }
		return .na
	}
}

/// possible variable types
public enum VariableType: Int {
	/// an unknown/unsupported variable
	case unknown,
	/// a variable whose .primitiveType will be set to a valid value
	primitive,
	/// a R Date object returned as a DateVariable object
	date,
	/// an R value of type POSIXct or POSIXlt as a DateVariable object
	dateTime,
	vector,
	matrix,
	array,
	list,
	/// returned as a FactorVariable
	factor,
	dataFrame,
	environment,
	function,
	s3Object,
	s4Object
	
	func isContainer() -> Bool {
		switch (self) {
		case .array, .dataFrame, .matrix, .list, .environment:
			return true
		default:
			return false
		}
	}
	
	static func forClass(_ name:String?) -> VariableType {
		guard let cname = name else { return .unknown }
		switch (cname) {
			case "data.frame":
				return .dataFrame
			case "matrix":
				return .matrix
			case "array":
				return .array
			case "list":
				return .list
			case "environment":
				return .environment
			case "function":
				return .function
			case "Date":
				return .date
			case "POSIXct", "POSIXlt":
				return .dateTime
			case "factor", "ordered factor":
				return .factor
			case "generic":
				return .s3Object
			case "S4":
				return .s4Object
			case "raw":
				return .primitive
			default:
				return .unknown
		}
	}
}

public class Variable: Equatable, CustomStringConvertible {
	fileprivate let jsonData:JSON

	public static func variableForJson(_ json:JSON) throws -> Variable {
		if json.getOptionalBool(at: "primitive")  {
			switch PrimitiveType.forString(json.getOptionalString(at: "type")) {
			case .boolean:
				return try BoolPrimitiveVariable(json: json)
			case .integer:
				return try IntPrimitiveVariable(json: json)
			case .double:
				return try DoublePrimitiveVariable(json: json)
			case .string, .complex:
				return try StringPrimitiveVariable(json: json)
			default:
				return try Variable(json: json)
			}
		}
		if json.getOptionalBool(at: "generic") {
			return try GenericVariable(json: json)
		}
		switch json.getOptionalString(at: "type", or: "") {
			case "f":
				return try FactorVariable(json: json)
			case "date":
				return try DateVariable(json: json)
			default:
				break
		}
		return try Variable(json:json)
	}
	
	public var name:String? { return jsonData.getOptionalString(at: "name") }
	/// for nested values, the fully qualified name (e.g. foo[0][1][2])
	public var fullyQualifiedName:String? { return name }
	///from R
	public var classNameR:String {
		if let klass = jsonData.getOptionalString(at: "class") {
			return klass
		}
		return "<unknown>"
	}
	/// a string representation of the value for display. e.g. for a factor, the name and number of possible values
	public var description: String { return "\(classNameR)[\(length)]" }
	///a more descriptive description: e.g. for a factor, list all the values
	public var summary:String {
		if let summ = jsonData.getOptionalString(at: "summary"), summ.utf8.count > 0 {
			return summ
		}
		return description
	}

	///the type of the variable
	public let type: VariableType
	///if type == .Primitive, that value. Otherwise, .NA
	public let primitiveType: PrimitiveType
	
	//the number of values in this variable locally (since all R variables are vectors)
	public var count:Int { return 0 }
	//the number of values in this variable on the server (since all R variables are vectors)
	public var length: Int { return jsonData.getOptionalInt(at: "length") ?? 0 }
	
	fileprivate init(json:JSON) throws {
		jsonData = json
		primitiveType = PrimitiveType.forString(jsonData.getOptionalString(at: "type"))
		if case .na = primitiveType {
			type = VariableType.forClass(jsonData.getOptionalString(at: "class"))
		} else {
			type = VariableType.primitive
		}
	}

	public var isPrimitive:Bool { return type == .primitive }
	public var isFactor:Bool { return type == .factor }
	public var isDate:Bool { return type == .date }
	public var isDateTime:Bool { return type == .dateTime }

	///if a string primitive type, returns the requested string value
	public func stringValueAtIndex(_ index:Int) -> String? { return nil }
	///if an Int primitive type, returns the requested Int value
	public func intValueAtIndex(_ index:Int) -> Int? { return nil }
	///if a Bool primitive type, returns the requested Bool value
	public func boolValueAtIndex(_ index:Int) -> Bool? { return nil }
	///if the primitive type is a Double, returns the requested string value
	public func doubleValueAtIndex(_ index:Int) -> Double? { return nil }
	///returns the value as a primitive type that can be downcast
	public func primitiveValueAtIndex(_ index:Int) -> PrimitiveValue? {
		switch(primitiveType) {
		case .boolean:
			return boolValueAtIndex(index)
		case .integer:
			return intValueAtIndex(index)
		case .double:
			return doubleValueAtIndex(index)
		case .string, .complex:
			return stringValueAtIndex(index)
		case .null:
			return nil
		default:
			return nil
		}
	}
	///if contains variables (list, array, S3, S4) returns nested variable
	public func variableAtIndex(_ index:Int) -> Variable? { return nil }
	
	///if a function type, returns the source code for the function
	public var functionBody:String? { return nil }
	///if a factor, returns the levels
	public var levels:[String]? { return nil }
	
	public static func == (lhs: Variable, rhs: Variable) -> Bool {
		return lhs.jsonData == rhs.jsonData
	}
}

public protocol PrimitiveValue {}
extension Bool: PrimitiveValue {}
extension Int: PrimitiveValue {}
extension Double: PrimitiveValue {}
extension String: PrimitiveValue {}
extension NSNull: PrimitiveValue {}

public final class BoolPrimitiveVariable: Variable {
	fileprivate let values:[Bool]
	
	override init(json: JSON) throws {
		values = try json.decodedArray(at: "value")
		try super.init(json: json)
	}
	
	override public var count:Int { return values.count }

	override public func boolValueAtIndex(_ index: Int) -> Bool? {
		return values[index]
	}

	override public func stringValueAtIndex(_ index: Int) -> String? {
		return String(describing: values[index])
	}
	
	override public var description: String {
		return "[\((values.map() { String($0) }).joined(separator: ", "))]"
	}
}

public final class IntPrimitiveVariable: Variable {
	fileprivate let values:[Int]
	
	override init(json: JSON) throws {
		values = try json.decodedArray(at: "value")
		try super.init(json: json)
	}
	
	override public var count:Int { return values.count }
	
	override public func stringValueAtIndex(_ index: Int) -> String? {
		return String(describing: values[index])
	}
	
	override public func intValueAtIndex(_ index: Int) -> Int? {
		return values[index]
	}
	
	override public func doubleValueAtIndex(_ index: Int) -> Double? {
		return Double(intValueAtIndex(index) ?? 0)
	}

	override public var description: String {
		return "[\((values.map() { String($0) }).joined(separator: ", "))]"
	}
}

public final class DoublePrimitiveVariable: Variable {
	fileprivate let values:[Double]
	
	override init(json: JSON) throws {
		let vals = try json.getArray(at: "value")
		values = try vals.map() { (val) in
			switch val {
			case .string(let str):
				if str == "Inf" { return Double.infinity }
				if str == "-Inf" { return Double(kCFNumberNegativeInfinity) }
				if str == "NaN" { return Double.nan }
				return Double.nan
			case .double(let dval):
				return dval
			case .int(let ival):
				return Double(ival)
			default:
				throw Rc2Error(type: .invalidJson, severity: .warning, explanation: "error parsing varaible json")
			}
		}
		try super.init(json: json)
	}
	
	override public var count:Int { return values.count }
	
	override public func doubleValueAtIndex(_ index: Int) -> Double? {
		return values[index]
	}
	
	override public func stringValueAtIndex(_ index: Int) -> String? {
		return String(describing: values[index])
	}
	
	override public var description: String {
		return "[\((values.map() { String($0) }).joined(separator: ", "))]"
	}
}

public final class StringPrimitiveVariable: Variable {
	fileprivate let values:[String]
	
	override init(json: JSON) throws {
		values = try json.decodedArray(at: "value")
		try super.init(json: json)
	}
	
	override public var count:Int { return values.count }
	
	override public func stringValueAtIndex(_ index: Int) -> String? {
		return values[index]
	}

	override public var description: String {
		if primitiveType == .complex {
			return "[\((values.map() { String($0) }).joined(separator: ", "))]"
		}
		return "[\((values.map() { "\"\($0)\"" }).joined(separator: ", "))]"
	}
}

public final class FactorVariable: Variable {
	fileprivate let values:[Int]
	fileprivate let levelNames:[String]
	
	override init(json: JSON) throws {
		values = try json.decodedArray(at: "value").map { $0 - 1 }
		levelNames = try json.decodedArray(at: "levels")
		try super.init(json: json)
	}
	
	override public var count:Int { return values.count }
	
	override public var levels:[String]? { return levelNames }

	override public func intValueAtIndex(_ index: Int) -> Int? {
		return values[index]
	}

	override public func stringValueAtIndex(_ index: Int) -> String? {
		return levelNames[values[index]]
	}
	
	override public var description: String {
		return "[\((values.map() { levelNames[$0] }).joined(separator: ", "))]"
	}
}

public final class DateVariable: Variable {
	public static let dateFormatter: DateFormatter = {
		let df = DateFormatter()
		df.locale = Locale(identifier: "en_US_POSIX")
		df.dateFormat = "yyyy-MM-dd"
		df.timeZone = TimeZone(secondsFromGMT: 0)
		return df
	}()

	public static let dateTimeFormatter: DateFormatter = {
		let df = DateFormatter()
		df.locale = Locale(identifier: "en_US_POSIX")
		df.dateFormat = "yyyy-MM-dd HH:mm:ss"
		df.timeZone = TimeZone(secondsFromGMT: 0)
		return df
	}()
	
	fileprivate var value: Date = Date() //has to be var so can set after super constructor
	
	public var date: Date { return value }
	
	override init(json: JSON) throws {
		try super.init(json: json)
		switch type {
			case .date:
				guard let dateVal = DateVariable.dateFormatter.date(from: try json.getString(at: "value")) else {
					throw Rc2Error(type: .invalidJson, severity: .warning, explanation: "error parsing date varaible json")
				}
				value = dateVal
			case .dateTime:
				value = Date(timeIntervalSince1970: try json.getDouble(at: "value"))
			default:
				throw Rc2Error(type: .invalidJson, severity: .warning, explanation: "error parsing date varaible json")
		}
	}

	override public func stringValueAtIndex(_ index: Int) -> String? {
		switch type {
		case .date:
			return DateVariable.dateFormatter.string(from: value)
		case .dateTime:
			return DateVariable.dateTimeFormatter.string(from: value)
		default:
			assertionFailure("invalid date format")
			return nil
		}
	}
	
}

public final class GenericVariable: Variable {
	fileprivate let values:[Variable]
	
	override init(json: JSON) throws {
		values = try json.getArray(at: "value").map { try Variable.variableForJson($0) }
		try super.init(json: json)
	}
	
	override public var count:Int { return values.count }
	
	override public func stringValueAtIndex(_ index: Int) -> String? {
		return values[index].description
	}
	
	override public func variableAtIndex(_ index:Int) -> Variable? { return values[index] }
}
