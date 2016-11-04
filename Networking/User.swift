//
//  User.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Freddy

public struct User: JSONDecodable, CustomStringConvertible, Equatable
{
	let userId: Int
	let login: String
	let version: Int
	let firstName: String
	let lastName: String
	let email: String
	let admin: Bool

	public init(json: JSON) throws {
		userId = try json.getInt(at: "id")
		version = try json.getInt(at: "version")
		login = try json.getString(at: "login")
		firstName = try json.getString(at: "firstName")
		lastName = try json.getString(at: "lastName")
		email = try json.getString(at: "email")
		admin = try json.getBool(at: "admin")
	}
	
	public var description: String {
		return "<User: \(login) \(userId)"
	}
	
	public static func == (lhs: User, rhs: User) -> Bool {
		return lhs.userId == rhs.userId && lhs.version == rhs.version
	}
}
