//
//  Process+Rc2.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

public extension ProcessInfo {
	/// Get an environemnt variable, or a default value if no such variable exists (or has a length of 0)
	///
	/// - Parameters:
	///   - name: the environment variable to lookup
	///   - defaultValue: the value to return instead of nil or if the length is 0
	/// - Returns: the environment variable, or the defaultValue
	public func envValue(name: String, defaultValue: String) -> String {
		guard let envVal = ProcessInfo.processInfo.environment[name], envVal.characters.count > 0 else {
			return defaultValue
		}
		return envVal
	}
}
