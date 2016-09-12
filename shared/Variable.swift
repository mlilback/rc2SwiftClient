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
	
	static func forString(_ typeCode:Swift.String?) -> PrimitiveType {
		guard let code = typeCode else { return .NA }
		if let val = PrimitiveType(rawValue: code) { return val }
		return .NA
	}
}

public enum VariableType: Int {
	case unknown,
	primitive,
	date,
	dateTime,
	vector,
	matrix,
	array,
	list,
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

open class Variable: NSObject {
	fileprivate let jsonData:JSON

	open static func variablesForJsonArray(_ array:[JSON]?) -> [Variable] {
		if nil == array { return [] }
		return array!.flatMap() { Variable.variableForJson($0) }
	}
	
	open static func variablesForJsonDictionary(_ dict:[String:JSON]?) -> [Variable] {
		if nil == dict { return [] }
		var array:[Variable] = []
		for (_,value) in dict! {
			array.append(Variable.variableForJson(value))
		}
		return array
	}
	
	open static func variableForJson(_ json:JSON) -> Variable {
		if json["primitive"].boolValue {
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
	
	open var name:String? { return jsonData["name"].string }
	/// for nested values, the fully qualified name (e.g. foo[0][1][2])
	open var fullyQualifiedName:String? { return name }
	///from R
	open var classNameR:String {
		if let klass = jsonData["class"].string {
			return klass
		}
		return "<unknown>"
	}
	/// a string representation of the value for display. e.g. for a factor, the name and number of possible values
	override open var description: String { return "\(classNameR)[\(length)]" }
	///a more descriptive description: e.g. for a factor, list all the values
	open var summary:String {
		if let summ = jsonData["summary"].string , summ.utf8.count > 0 {
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
	var length:Int { return jsonData["length"].intValue }
	
	init(json:JSON) {
		jsonData = json
		type = VariableType.forClass(jsonData["class"].string)
		primitiveType = PrimitiveType.forString(jsonData["type"].string)
	}

	var isPrimitive:Bool { return type == .primitive }
	var isFactor:Bool { return type == .factor }
	var isDate:Bool { return type == .date }
	var isDateTime:Bool { return type == .dateTime }

	///if a string primitive type, returns the requested string value
	open func stringValueAtIndex(_ index:Int) -> String? { return nil }
	///if an Int primitive type, returns the requested Int value
	open func intValueAtIndex(_ index:Int) -> Int? { return nil }
	///if a Bool primitive type, returns the requested Bool value
	open func boolValueAtIndex(_ index:Int) -> Bool? { return nil }
	///if the primitive type is a Double, returns the requested string value
	open func doubleValueAtIndex(_ index:Int) -> Double? { return nil }
	///returns the value as a primitive type that can be downcast
	open func primitiveValueAtIndex(_ index:Int) -> PrimitiveValue? {
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
	open func variableAtIndex(_ index:Int) -> Variable? { return nil }
	
	///if a function type, returns the source code for the function
	open var functionBody:String? { return nil }
	///if a factor, returns the levels
	open var levels:[String]? { return nil }
}

public protocol PrimitiveValue {}
extension Bool: PrimitiveValue {}
extension Int: PrimitiveValue {}
extension Double: PrimitiveValue {}
extension String: PrimitiveValue {}

open class BoolPrimitiveVariable: Variable {
	fileprivate let values:[Bool]
	
	override init(json: JSON) {
		self.values = json.dictionaryValue["value"]!.arrayValue.map() { $0.boolValue }
		super.init(json: json)
	}
	
	override var count:Int { return values.count }

	override open func boolValueAtIndex(_ index: Int) -> Bool? {
		return values[index]
	}

	override open var description: String {
		return "[\((values.map() { String($0) }).joined(separator: ", "))]"
	}
}

open class IntPrimitiveVariable: Variable {
	fileprivate let values:[Int]
	
	override init(json: JSON) {
		self.values = json.dictionaryValue["value"]!.arrayValue.map() { $0.intValue }
		super.init(json: json)
	}
	
	override var count:Int { return values.count }
	
	override open func intValueAtIndex(_ index: Int) -> Int? {
		return values[index]
	}
	
	override open func doubleValueAtIndex(_ index: Int) -> Double? {
		return Double(intValueAtIndex(index) ?? 0)
	}

	override open var description: String {
		return "[\((values.map() { String($0) }).joined(separator: ", "))]"
	}
}

open class DoublePrimitiveVariable: Variable {
	fileprivate let values:[Double]
	
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
	
	override open func doubleValueAtIndex(_ index: Int) -> Double? {
		return values[index]
	}
	
	override open var description: String {
		return "[\((values.map() { String($0) }).joined(separator: ", "))]"
	}
}

open class StringPrimitiveVariable: Variable {
	fileprivate let values:[String]
	
	override init(json: JSON) {
		self.values = json.dictionaryValue["value"]!.arrayValue.map() { $0.stringValue }
		super.init(json: json)
	}
	
	override var count:Int { return values.count }
	
	override open func stringValueAtIndex(_ index: Int) -> String? {
		return values[index]
	}

	override open var description: String {
		if primitiveType == .Complex {
			return "[\((values.map() { String($0) }).joined(separator: ", "))]"
		}
		return "[\((values.map() { "\"\($0)\"" }).joined(separator: ", "))]"
	}
}

open class FactorVariable: Variable {
	fileprivate let values:[Int]
	fileprivate let levelNames:[String]
	
	override init(json: JSON) {
		self.values = json.dictionaryValue["value"]!.arrayValue.map() { $0.intValue - 1 }
		self.levelNames = json.dictionaryValue["levels"]!.arrayValue.map() { $0.stringValue }
		super.init(json: json)
	}
	
	override var count:Int { return values.count }
	
	override open var levels:[String]? { return levelNames }

	override open func intValueAtIndex(_ index: Int) -> Int? {
		return values[index]
	}
	
	override open func stringValueAtIndex(_ index: Int) -> String? {
		return levelNames[values[index]]
	}
	
	override open var description: String {
		return "[\((values.map() { levelNames[$0] }).joined(separator: ", "))]"
	}
}

open class GenericVariable: Variable {
	fileprivate let values:[Variable]
	
	override init(json: JSON) {
		self.values = Variable.variablesForJsonArray(json.dictionaryValue["value"]!.arrayValue)
		super.init(json: json)
	}
	
	override var count:Int { return values.count }
	
	override open func stringValueAtIndex(_ index: Int) -> String? {
		return values[index].description
	}
	
	override open func variableAtIndex(_ index:Int) -> Variable? { return values[index] }
}
