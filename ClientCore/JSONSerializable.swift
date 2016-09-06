 //
//  JSONSerializable.swift
//  SwiftClient
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import SwiftyJSON

public protocol JSONSerializable {
	///for deserialization
	init?(json:JSON)
	
	func toJson() throws -> JSON
}
