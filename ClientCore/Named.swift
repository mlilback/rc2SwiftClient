//
//  Named.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

/// A protocol for types that have 1 or more names
public protocol Named: Equatable {
	func isNamed(_ str:String) -> Bool
}
