//
//  JSONSerializable.swift
//  SwiftClient
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import SwiftyJSON

public protocol JSONSerializable {
	func serialize() throws -> JSON
}

public enum JSONSerializableError: ErrorType {
	case UnsupportedType
}

extension JSONSerializable {
	public func serialize() throws -> JSON
	{
		let mirror = Mirror(reflecting: self)
		var dict = [String:JSON]()
		for case let (label?, value) in mirror.children {
			if let vstr = value as? String {
				dict[label] = JSON(["type":"String", "value":vstr])
			} else if let vint = value as? Int {
				dict[label] = JSON(["type":"Int", "value":vint])
			} else if let vf = value as? Float {
				dict[label] = JSON(["type":"Float", "value":vf])
			} else if let vdouble = value as? Double {
				dict[label] = JSON(["type":"Double", "value":vdouble])
			} else if let _ = value as? NSNull {
				dict[label] = JSON(["type":"Nil"])
			} else if let vbool = value as? Bool {
				dict[label] = JSON(["type":"Bool", "value":vbool])
			} else if let val = value as? NSDate {
				dict[label] = JSON(["type":"Date", "value":val.timeIntervalSinceReferenceDate])
			} else {
				throw JSONSerializableError.UnsupportedType
			}
		}
		return JSON(dict)
	}
}

public class JSONDserializer {
	/// - parameter json: JSON object to decode
	/// - returns: a dictionary of property names to values
	public static func deserialize(json:JSON) throws -> [String:AnyObject]
	{
		var results = [String:AnyObject]()
		for name in json.dictionaryValue.keys {
			let dict = json[name].dictionaryValue
			guard let type = dict["type"]?.string else { continue }
			switch(type) {
			case "String":
				results[name] = dict["value"]!.stringValue
			case "Int":
				results[name] = dict["value"]!.intValue
			case "Float":
				results[name] = dict["value"]!.floatValue
			case "Double":
				results[name] = dict["value"]!.doubleValue
			case "Bool":
				results[name] = dict["value"]!.boolValue
			case "Nil":
				results[name] = NSNull()
			case "Date":
				results[name] = NSDate(timeIntervalSinceReferenceDate: dict["value"]!.doubleValue)
			default:
				throw JSONSerializableError.UnsupportedType
			}
		}
		return results
	}
}
