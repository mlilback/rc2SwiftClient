//
//  Freddy+Rc2.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Freddy

extension JSON {
	/// Assuming self is an array, return self as an array of JSON
	///
	/// - throws: valueNotConvertible if self is not an .array
	/// - returns: self as an array of JSON
	func asJsonArray() throws -> [JSON] {
		guard case .array(let array) = self else {
			throw Error.valueNotConvertible(value: self, to: Array<JSON>.self)
		}
		return array
	}
	
	/// Assuming self is an array, decodes self to the desired type
	///
	/// - Returns: an array of the desired type
	/// - Throws: if self is not an array of json or if array elements aren't of desired type
	func asArray<Decoded: JSONDecodable>() throws -> [Decoded] {
		return try asJsonArray().map(Decoded.init)
	}

	/// Assuming self is an array, decodes self to the desired type
	///
	/// - Parameter of: the type of object to be decoded
	/// - Returns: an array of the desired type
	/// - Throws: if self is not an array of json or if array elements aren't of desired type
	func asArray<T:JSONDecodable>(of: T) throws -> [T] {
		return try asJsonArray().map(T.init)
	}
	
	/// Returns nil instead of throwing an error if value does not exist
	///
	/// - Parameter at: path type to get the value of
	/// - Returns: the requested value or nil
	func getOptionalString(at: JSONPathType) -> String? {
		guard let str = try? getString(at: at) else { return nil }
		return str
	}

	/// Returns default value instead of throwing an error if value does not exist
	///
	/// - Parameter at: path type to get the value of
	/// - Parameter or: the value to return if value does not exist
	/// - Returns: the value or default value
	func getOptionalString(at: JSONPathType, or: String) -> String {
		guard let str = try? getString(at: at) else { return or }
		return str
	}

	/// Returns nil instead of throwing an error if value does not exist
	///
	/// - Parameter at: path type to get the value of
	/// - Returns: the requested value or nil
	func getOptionalDobule(at: JSONPathType) -> Double? {
		guard let val = try? getDouble(at: at) else { return nil }
		return val
	}

	/// Returns nil instead of throwing an error if value does not exist
	///
	/// - Parameter at: path type to get the value of
	/// - Returns: the requested value or nil
	func getOptionalInt(at: JSONPathType) -> Int? {
		guard let val = try? getInt(at: at) else { return nil }
		return val
	}

	/// Returns nil instead of throwing an error if value does not exist
	///
	/// - Parameter at: path type to get the value of
	/// - Returns: the requested value or nil
	func getOptionalBool(at: JSONPathType, or: Bool = false) -> Bool {
		guard let val = try? getBool(at: at) else { return or }
		return val
	}
}
