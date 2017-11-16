//
//  VariableFormatter.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Model

/// Used to convert values of a variable to an array of strings
class VariableFormatter {
	let doubleFormatter: NumberFormatter
	let dateFormatter: DateFormatter
	let dateTimeFormatter: DateFormatter
	
	init(doubleFormatter: NumberFormatter, dateFormatter: DateFormatter, dateTimeFormatter: DateFormatter? = nil) {
		self.doubleFormatter = doubleFormatter
		self.dateFormatter = dateFormatter
		self.dateTimeFormatter = dateTimeFormatter ?? dateFormatter
	}
	
	/// Returns an array of strings for the values of the variable
	///
	/// - Parameter variable: the variable to get the values of
	/// - Returns: the values as Strings, or nil if formatting not supported
	public func formatValues(for variable: Variable) -> [String]? {
		switch variable.type {
		case .primitive(let pval):
			return formatValues(for: pval)
		case .date(let dval):
			return [dateFormatter.string(from: dval)]
		case .dateTime(let dval):
			return [dateTimeFormatter.string(from: dval)]
		default:
			return nil
		}
	}
	
	/// Returns values as an array of strings
	///
	/// - Parameter primitive: the primitive value to retrieve values from
	/// - Returns: the value array as an array of formatted strings
	public func formatValues(for primitive: PrimitiveValue) -> [String] {
		switch primitive {
		case .boolean(let boolVals):
			return boolVals.map { $0.description }
		case .integer(let intVals):
			return intVals.map { $0.description }
		case .double(let doubleVals):
			return doubleVals.map { doubleFormatter.string(from: NSNumber(value: $0)) ?? "-" }
		case .string(let strVals):
			return strVals
		case .complex(let complexVals):
			return complexVals
		case .raw:
			return ["<RAW>"]
		case .null:
			return ["NULL"]
		}
	}
}

