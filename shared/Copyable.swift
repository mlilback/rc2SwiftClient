//
//  Copyable.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

/// allows copying of a class object
public protocol Copyable: AnyObject {
	/// creates a copy of the passed in object
	/// - Parameter instance: an instance of Self to create a copy of
	init(instance: Self)
}

public extension Copyable {
	/// create a copy of self
	/// - returns: a copy of self
	func copy() -> Self {
		return Self.init(instance: self)
	}
}

public extension Array where Element: Copyable {
	/// return a copy of the array with copies of all the elements
	func copy() -> [Element] {
		var outArray: [Element] = []
		forEach { elem in outArray.append(elem.copy()) }
		return outArray
	}
}
