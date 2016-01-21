//
//  LoginSession.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import SwiftyJSON

public struct LoginSession: CustomStringConvertible {
	let host : String;
	let authToken : String;
	let currentUser : User;
	var workspaces : [Workspace];
	
	init(json : JSON, host : String) {
		self.host = host
		authToken = json["token"].stringValue
		currentUser = User(json: json["user"])
		workspaces = Workspace.workspacesFromJsonArray(json["workspaces"])
	}
	
	func workspaceWithName(name:String) -> Workspace? {
		if let found = workspaces.indexOf({$0.name == name}) {
			return workspaces[found]
		}
		return nil
	}

	public var description : String {
		return "<LoginSession: \(currentUser.login)@\(host) (\(currentUser.userId))";
	}
}