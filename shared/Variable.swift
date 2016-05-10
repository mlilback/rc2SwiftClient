//
//  VariableEnums.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import SwiftyJSON

public enum PrimitiveType: String {
	case Boolean = "b",
	Integer = "i",
	Double = "d",
	String = "s",
	Complex = "c",
	Raw = "r",
	Null = "n",
	NA = "na" ///never sent from server. used for objects that aren't a primitive
	
	static func forString(typeCode:Swift.String?) -> PrimitiveType {
		guard let code = typeCode else { return .NA }
		if let val = PrimitiveType(rawValue: code) { return val }
		return .NA
	}
}

public enum VariableType: Int {
	case Unknown,
	Primitive,
	Date,
	DateTime,
	Vector,
	Matrix,
	Array,
	List,
	Factor,
	DataFrame,
	Environment,
	Function,
	S3Object,
	S4Object
	
	func isContainer() -> Bool {
		switch (self) {
		case .Array, .DataFrame, .Matrix, .List, .Environment:
			return true
		default:
			return false
		}
	}
	
	static func forClass(name:String?) -> VariableType {
		guard let cname = name else { return .Unknown }
		switch (cname) {
			case "data.frame":
				return .DataFrame
			case "matrix":
				return .Matrix
			case "array":
				return .Array
			case "list":
				return .List
			case "environment":
				return .Environment
			case "function":
				return .Function
			case "Date":
				return .Date
			case "POSIXct", "POSIXlt":
				return .DateTime
			case "factor", "ordered factor":
				return .Factor
			case "generic":
				return .S3Object
			case "S4":
				return .S4Object
			case "raw":
				return .Primitive
			default:
				return .Unknown
		}
	}
}

public class Variable: NSObject {
	private let jsonData:JSON

	public static func variablesForJsonArray(array:[JSON]?) -> [Variable] {
		if nil == array { return [] }
		return array!.flatMap() { Variable.variableForJson($0) }
	}
	
	public static func variablesForJsonDictionary(dict:[String:JSON]?) -> [Variable] {
		if nil == dict { return [] }
		var array:[Variable] = []
		for (_,value) in dict! {
			array.append(Variable.variableForJson(value))
		}
		return array
	}
	
	public static func variableForJson(json:JSON) -> Variable {
		if json["primitive"].boolValue ?? false {
			switch (PrimitiveType.forString(json["type"].stringValue)) {
			case .Boolean:
				return BoolPrimitiveVariable(json: json)
			case .Integer:
				return IntPrimitiveVariable(json: json)
			case .Double:
				return DoublePrimitiveVariable(json: json)
			case .String, .Complex:
				return StringPrimitiveVariable(json: json)
			default:
				return Variable(json: json)
			}
		}
		if json["generic"].boolValue || false {
			return GenericVariable(json: json)
		}
		switch (json["type"]) {
			case "f":
				return FactorVariable(json:json)
			default:
				break
		}
		return Variable(json:json)
	}
	
	public var name:String? { return jsonData["name"].string }
	/// for nested values, the fully qualified name (e.g. foo[0][1][2])
	public var fullyQualifiedName:String? { return name }
	///from R
	public var classNameR:String {
		if let klass = jsonData["class"].string {
			return klass
		}
		return "<unknown>"
	}
	/// a string representation of the value for display. e.g. for a factor, the name and number of possible values
	override public var description: String { return "\(classNameR)[\(length)]" }
	///a more descriptive description: e.g. for a factor, list all the values
	public var summary:String {
		if let summ = jsonData["summary"].string where summ.utf8.count > 0 {
			return summ
		}
		return description
	}

	///the type of the variable
	let type:VariableType
	///if type == .Primitive, that value. Otherwise, .NA
	let primitiveType:PrimitiveType
	
	//the number of values in this variable locally (since all R variables are vectors)
	var count:Int { return 0 }
	//the number of values in this variable on the server (since all R variables are vectors)
	var length:Int { return jsonData["length"].intValue ?? self.count }
	
	init(json:JSON) {
		jsonData = json
		type = VariableType.forClass(jsonData["class"].string)
		primitiveType = PrimitiveType.forString(jsonData["type"].string)
	}

	var isPrimitive:Bool { return type == .Primitive }
	var isFactor:Bool { return type == .Factor }
	var isDate:Bool { return type == .Date }
	var isDateTime:Bool { return type == .DateTime }

	///if a string primitive type, returns the requested string value
	public func stringValueAtIndex(index:Int) -> String? { return nil }
	///if an Int primitive type, returns the requested Int value
	public func intValueAtIndex(index:Int) -> Int? { return nil }
	///if a Bool primitive type, returns the requested Bool value
	public func boolValueAtIndex(index:Int) -> Bool? { return nil }
	///if the primitive type is a Double, returns the requested string value
	public func doubleValueAtIndex(index:Int) -> Double? { return nil }
	///returns the value as a primitive type that can be downcast
	public func primitiveValueAtIndex(index:Int) -> PrimitiveValue? {
		switch(primitiveType) {
		case .Boolean:
			return boolValueAtIndex(index)
		case .Integer:
			return intValueAtIndex(index)
		case .Double:
			return doubleValueAtIndex(index)
		case .String:
			return stringValueAtIndex(index)
		default:
			return nil
		}
	}
	///if contains variables (list, array, S3, S4) returns nested variable
	public func variableAtIndex(index:Int) -> Variable? { return nil }
	
	///if a function type, returns the source code for the function
	public var functionBody:String? { return nil }
	///if a factor, returns the levels
	public var levels:[String]? { return nil }
}

public protocol PrimitiveValue {}
extension Bool: PrimitiveValue {}
extension Int: PrimitiveValue {}
extension Double: PrimitiveValue {}
extension String: PrimitiveValue {}

public class BoolPrimitiveVariable: Variable {
	private let values:[Bool]
	
	override init(json: JSON) {
		self.values = json.dictionaryValue["value"]!.arrayValue.map() { $0.boolValue }
		super.init(json: json)
	}
	
	override var count:Int { return values.count }

	override public func boolValueAtIndex(index: Int) -> Bool? {
		return values[index]
	}

	override public var description: String {
		return "[\((values.map() { String($0) }).joinWithSeparator(", "))]"
	}
}

public class IntPrimitiveVariable: Variable {
	private let values:[Int]
	
	override init(json: JSON) {
		self.values = json.dictionaryValue["value"]!.arrayValue.map() { $0.intValue }
		super.init(json: json)
	}
	
	override var count:Int { return values.count }
	
	override public func intValueAtIndex(index: Int) -> Int? {
		return values[index]
	}
	
	override public func doubleValueAtIndex(index: Int) -> Double? {
		return Double(intValueAtIndex(index) ?? 0)
	}

	override public var description: String {
		return "[\((values.map() { String($0) }).joinWithSeparator(", "))]"
	}
}

public class DoublePrimitiveVariable: Variable {
	private let values:[Double]
	
	override init(json: JSON) {
		self.values = json.dictionaryValue["value"]!.arrayValue.map() {
			if let str = $0.string {
				if str == "Inf" { return Double.infinity }
				if str == "-Inf" { return (kCFNumberNegativeInfinity as NSNumber).doubleValue }
				return kCFNumberNaN as Double
			}
			return $0.doubleValue
		}
		super.init(json: json)
	}
	
	override var count:Int { return values.count }
	
	override public func doubleValueAtIndex(index: Int) -> Double? {
		return values[index]
	}
	
	override public var description: String {
		return "[\((values.map() { String($0) }).joinWithSeparator(", "))]"
	}
}

public class StringPrimitiveVariable: Variable {
	private let values:[String]
	
	override init(json: JSON) {
		self.values = json.dictionaryValue["value"]!.arrayValue.map() { $0.stringValue }
		super.init(json: json)
	}
	
	override var count:Int { return values.count }
	
	override public func stringValueAtIndex(index: Int) -> String? {
		return values[index]
	}

	override public var description: String {
		if primitiveType == .Complex {
			return "[\((values.map() { String($0) }).joinWithSeparator(", "))]"
		}
		return "[\((values.map() { "\"\(String($0))\"" }).joinWithSeparator(", "))]"
	}
}

public class FactorVariable: Variable {
	private let values:[Int]
	private let levelNames:[String]
	
	override init(json: JSON) {
		self.values = json.dictionaryValue["value"]!.arrayValue.map() { $0.intValue - 1 }
		self.levelNames = json.dictionaryValue["levels"]!.arrayValue.map() { $0.stringValue }
		super.init(json: json)
	}
	
	override var count:Int { return values.count }
	
	override public var levels:[String]? { return levelNames }

	override public func intValueAtIndex(index: Int) -> Int? {
		return values[index]
	}
	
	override public func stringValueAtIndex(index: Int) -> String? {
		return levelNames[values[index]]
	}
	
	override public var description: String {
		return "[\((values.map() { levelNames[$0] }).joinWithSeparator(", "))]"
	}
}

public class GenericVariable: Variable {
	private let values:[Variable]
	
	override init(json: JSON) {
		self.values = Variable.variablesForJsonArray(json.dictionaryValue["value"]!.arrayValue)
		super.init(json: json)
	}
	
	override var count:Int { return values.count }
	
	override public func stringValueAtIndex(index: Int) -> String? {
		return values[index].description
	}
	
	override public func variableAtIndex(index:Int) -> Variable? { return values[index] }
}
