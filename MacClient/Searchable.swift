//
//  Searchable.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

protocol Searchable {
	func performFind(action: NSTextFinderAction)
}

extension Searchable {
	func performFind(action: NSTextFinderAction) { }
}
