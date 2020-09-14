//
//  Encoding.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

/// a base encoder protocol for abstracting JSONEncoder, PropertyListEncoder, etc.
public protocol SwiftEncoder {
	func encode<T>(_ value: T) throws -> Data where T: Encodable
}

extension JSONEncoder: SwiftEncoder {}

extension PropertyListEncoder: SwiftEncoder {}

/// a base decoder protocol for abstracting JSONDecoder, PropertyListDecoder, etc.
public protocol SwiftDecoder {
	func decode<T>(_ type: T.Type, from data: Data) throws -> T where T: Decodable
}

extension JSONDecoder: SwiftDecoder {}

extension PropertyListDecoder: SwiftDecoder {}
