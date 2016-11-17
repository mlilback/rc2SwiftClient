//
//  ServerHost.swift
//  SwiftClient
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Freddy

///Represents a remote host
public struct ServerHost: JSONDecodable, JSONEncodable, CustomStringConvertible, Hashable {
	
	public static let localHost:ServerHost = { return ServerHost(name: "Local Server", host: "localhost", port: 8088, user: "local", secure: false) }()
	///user-friendly name for the host
	public let name:String
	public let host:String
	public let user:String
	public let port:Int
	public let secure:Bool
	
	/// the string used to store the password for this host in the keychain
	public var keychainKey:String { return "\(self.user)@\(self.host)" }
	
	public init(name:String, host:String, port:Int=8088, user:String="local", secure:Bool=false) {
		self.name = name
		self.host = host
		self.user = user
		self.port = port
		self.secure = secure
	}
	
	/// convenience initializer that return nil if an error was thrown by the JSON initializer
	public init?(from: JSON) {
		do {
			try self.init(json: from)
		} catch {
		}
		return nil
	}

	//documentation inherited from protocol
	public init(json dict:JSON) throws {
		self.name = try dict.getString(at: "name")
		self.host = try dict.getString(at: "host")
		self.user = try dict.getString(at: "user")
		self.port = try dict.getInt(at: "port")
		self.secure = try dict.getBool(at: "secure")
	}

	/// a URL for this server
	public var url: URL? {
		var components = URLComponents()
		components.host = host
		components.port = port
		components.scheme = secure ? "https" : "http"
		return components.url
	}
	
	//documentation inherited from protocol
	public func toJSON() -> JSON {
		return .dictionary(["name": .string(name), "host": .string(host), "user": .string(user), "port": .int(port), "secure": .bool(secure)])
	}

	//documentation inherited from protocol
	public var description: String {
		return "ServerHost \(name) \(user )@(\(host):\(port) \(secure ? "secure" : ""))"
	}
	
	//documentation inherited from protocol
	public var hashValue: Int { return name.hashValue ^ host.hashValue ^ port.hashValue ^ secure.hashValue }
}

public func ==(left:ServerHost, right:ServerHost) -> Bool {
	return left.name == right.name && left.host == right.host && left.port == right.port && left.secure == right.secure && left.user == right.user
}
