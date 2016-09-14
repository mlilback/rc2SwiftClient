//
//  Bookmark.swift
//  SwiftClient
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import SwiftyJSON
import ClientCore

/// represents a bookmark to an rc2 server
public struct Bookmark: JSONSerializable, CustomStringConvertible, Equatable {
	let name:String
	let server:ServerHost?
	let projectName:String
	let workspaceName:String?
	var lastUsed:TimeInterval
	
	init(name:String, server:ServerHost?, project:String, workspace:String?, lastUsed:TimeInterval = 0) {
		self.name = name
		self.server = server
		self.projectName = project
		self.workspaceName = workspace
		self.lastUsed = lastUsed
	}
	
	public init?(json:JSON) {
		name = json["name"].stringValue
		projectName = json["project"].stringValue
		workspaceName = json["workspace"].stringValue
		lastUsed = json["lastUsed"].doubleValue
		if let _ = json["server"].dictionary {
			server = ServerHost(json: json["server"])
		} else {
			server = nil
		}
	}
	
	public func serialize() throws -> JSON {
		var dict = [String:JSON]()
		dict["name"] = JSON(name)
		dict["project"] = JSON(projectName)
		if let wsname = workspaceName {
			dict["workspace"] = JSON(wsname)
		}
		dict["lastUsed"] = JSON(lastUsed)
		dict["server"] = try server?.serialize()
		return JSON(dict)
	}
	
	public func withChangedName(_ newName:String) -> Bookmark {
		return Bookmark(name: newName, server: server, project: projectName, workspace: workspaceName, lastUsed: lastUsed)
	}
	
	public var description:String { return "<Bookmark: \(name)" }
}

public func ==(lhs:Bookmark, rhs:Bookmark) -> Bool {
	return lhs.name == rhs.name && lhs.server == rhs.server && lhs.projectName == rhs.projectName && lhs.workspaceName == rhs.workspaceName && lhs.lastUsed == rhs.lastUsed
}
