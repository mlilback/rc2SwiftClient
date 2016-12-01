//
//  Freddy+Rc2.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Freddy

public extension JSON {
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
	func getOptionalDouble(at: JSONPathType) -> Double? {
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

	/// Returns default value instead of throwing an error if value does not exist
	///
	/// - Parameter at: path type to get the value of
	/// - Returns: the requested value or default value
	func getOptionalInt(at: JSONPathType, or: Int) -> Int {
		guard let val = try? getInt(at: at) else { return or }
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
