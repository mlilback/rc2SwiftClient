//
//  Result+Rc2.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Result

public extension Result where Value: Equatable, Error: Equatable {
	static func == (lhs: Result<Value, Error>, rhs: Result<Value, Error>) -> Bool {
		return lhs.error == rhs.error && lhs.value == rhs.value
	}
}
