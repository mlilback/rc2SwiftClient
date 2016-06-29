//
//  Bookmark.swift
//  SwiftClient
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import SwiftyJSON

/// represents a bookmark to an rc2 server
public struct Bookmark: JSONSerializable, CustomStringConvertible, Equatable {
	let name:String
	let server:ServerHost?
	let projectName:String
	let workspaceName:String?
	var lastUsed:NSTimeInterval
	
	static func bookmarksFromJsonArray(jsonArray:[JSON]) -> [Bookmark] {
		var bmarks = [Bookmark]()
		for aJsonObj in jsonArray {
			bmarks.append(Bookmark(json: aJsonObj)!)
		}
		return bmarks
	}
	
	init(name:String, server:ServerHost?, project:String, workspace:String?) {
		self.name = name
		self.server = server
		self.projectName = project
		self.workspaceName = workspace
		lastUsed = 0
	}
	
	public init?(json:JSON) {
		name = json["name"].stringValue
		projectName = json["project"].stringValue
		workspaceName = json["workspace"].stringValue
		lastUsed = json["lastUsed"].doubleValue
		server = ServerHost(json: json["server"])
	}
	
	public func serialize() throws -> JSON {
		var dict = [String:JSON]()
		dict["name"] = JSON(name)
		dict["project"] = JSON(projectName)
		dict["workspace"] = JSON(workspaceName == nil ? NSNull() : workspaceName!)
		dict["lastUsed"] = JSON(lastUsed)
		dict["server"] = try server?.serialize()
		return JSON(dict)
	}
	
	public var description:String { return "<Bookmark: \(name)" }
}

public func ==(lhs:Bookmark, rhs:Bookmark) -> Bool {
	return lhs.name == rhs.name && lhs.server == rhs.server && lhs.projectName == rhs.projectName && lhs.workspaceName == rhs.workspaceName && lhs.lastUsed == rhs.lastUsed
}
