//
//  LoginSession.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import SwiftyJSON

public class LoginSession: CustomStringConvertible {
	let host : String;
	let authToken : String;
	let currentUser : User;
	var projects : [Project];
	
	init(json : JSON, host : String) {
		self.host = host
		authToken = json["token"].stringValue
		currentUser = User(json: json["user"])
		projects = Project.projectsFromJsonArray(json["projects"])
	}
	
	func projectWithName(name:String) -> Project? {
		if let found = projects.indexOf({$0.name == name}) {
			return projects[found]
		}
		if name == "Default" {
			return projects.first
		}
		return nil
	}

	public var description : String {
		return "<LoginSession: \(currentUser.login)@\(host) (\(currentUser.userId))";
	}
}