//
//  User.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import SwiftyJSON

open class User: CustomStringConvertible, Equatable {
	let userId : Int32;
	let login : String;
	let version : Int32;
	let firstName: String;
	let lastName: String;
	let email: String;
	let admin: Bool;
	
	convenience init (jsonData:AnyObject) {
		let json = JSON(jsonData)
		self.init(json: json)
	}
	
	init(json : JSON) {
		userId = json["id"].int32Value
		login = json["login"].stringValue
		version = json["version"].int32Value
		firstName = json["firstName"].stringValue
		lastName = json["lastName"].stringValue
		email = json["email"].stringValue
		admin = json["admin"].boolValue
	}
	
	open var description : String {
		return "<User: \(login) (\(userId))";
	}
}

public func ==(a:User, b:User) -> Bool {
	return a.userId == b.userId && a.version == b.version
}
