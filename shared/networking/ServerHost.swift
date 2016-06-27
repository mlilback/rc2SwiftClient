//
//  ServerHost.swift
//  SwiftClient
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import SwiftyJSON

///Represents a remote host
public struct ServerHost: CustomStringConvertible, Hashable {
	///load array of josts from a json file with a dictionary with an array stored under the key of "hosts"
	public static func loadHosts(fromUrl:NSURL) -> [ServerHost] {
		let jsonData = NSData(contentsOfURL: fromUrl)
		let json = JSON(data:jsonData!)
		let theHosts = json["hosts"].arrayValue
		assert(theHosts.count > 0, "invalid hosts data")
		return theHosts.map() { ServerHost(dict: $0) }
	}
	
	///user-friendly name for the host
	let name:String
	let host:String
	let port:Int
	let secure:Bool
	
	init(name:String, host:String, port:Int, secure:Bool) {
		self.name = name
		self.host = host
		self.port = port
		self.secure = secure
	}
	
	init(dict:JSON) {
		self.name = dict["name"].stringValue
		self.host = dict["host"].stringValue
		self.port = dict["port"].intValue
		self.secure = dict["secure"].boolValue
	}
	
	public var description: String {
		return "ServerHost \(name) (\(host):\(port) \(secure ? "secure" : ""))"
	}
	
	public var hashValue: Int { return name.hashValue ^ host.hashValue ^ port.hashValue ^ secure.hashValue }
}

public func ==(left:ServerHost, right:ServerHost) -> Bool {
	return left.name == right.name && left.host == right.host && left.port == right.port && left.secure == right.secure
}
