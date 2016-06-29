//
//  ServerHost.swift
//  SwiftClient
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import SwiftyJSON

///Represents a remote host
public struct ServerHost: JSONSerializable, CustomStringConvertible, Hashable {
	
	///user-friendly name for the host
	let name:String
	let host:String
	let user:String
	let port:Int
	let secure:Bool
	
	init(name:String, host:String, port:Int=8088, user:String="test", secure:Bool=false) {
		self.name = name
		self.host = host
		self.user = user
		self.port = port
		self.secure = secure
	}
	
	public init?(json dict:JSON) {
		self.name = dict["name"].stringValue
		self.host = dict["host"].stringValue
		self.user = dict["user"].stringValue
		self.port = dict["port"].intValue
		self.secure = dict["secure"].boolValue
	}

	public func serialize() throws -> JSON {
		var dict = [String:AnyObject]()
		dict["name"] = name
		dict["host"] = host
		dict["port"] = port
		dict["user"] = user
		dict["secure"] = secure
		return JSON(dict)
	}

	public var description: String {
		return "ServerHost \(name) \(user ?? "")@(\(host):\(port) \(secure ? "secure" : ""))"
	}
	
	public var hashValue: Int { return name.hashValue ^ host.hashValue ^ port.hashValue ^ secure.hashValue }
}

public func ==(left:ServerHost, right:ServerHost) -> Bool {
	return left.name == right.name && left.host == right.host && left.port == right.port && left.secure == right.secure && left.user == right.user
}
