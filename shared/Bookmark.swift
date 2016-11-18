//
//  Bookmark.swift
//  SwiftClient
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Freddy
import ClientCore
import Networking

/// represents a bookmark to an rc2 server
public struct Bookmark: JSONDecodable, JSONEncodable, CustomStringConvertible, Equatable {
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
	
	/// convenience initializer that return nil if an error was thrown by the JSON initializer
	public init?(from: JSON) {
		do {
			try self.init(json: from)
		} catch {
		}
		return nil
	}

	public init(json:JSON) throws {
		name = try json.getString(at: "name")
		projectName = try json.getString(at: "project")
		workspaceName = try json.getString(at: "workspace")
		lastUsed = try json.getDouble(at: "lastUsed")
		if let host = try? json.decode(at: "server", type: ServerHost.self) {
			server = host
		} else {
			server = nil
		}
	}
	
	public func toJSON() -> JSON {
		let wspaceJson: JSON = (workspaceName == nil) ? .null : .string(workspaceName!)
		let hostJson = server?.toJSON() ?? .null
		return .dictionary(["name": .string(name), "project": .string(projectName), "workspace": wspaceJson, "lastUsed": .double(lastUsed), "server": hostJson])
	}
	
	public func withChangedName(_ newName:String) -> Bookmark {
		return Bookmark(name: newName, server: server, project: projectName, workspace: workspaceName, lastUsed: lastUsed)
	}
	
	public var description:String { return "<Bookmark: \(name)" }
}

public func ==(lhs:Bookmark, rhs:Bookmark) -> Bool {
	return lhs.name == rhs.name && lhs.server == rhs.server && lhs.projectName == rhs.projectName && lhs.workspaceName == rhs.workspaceName && lhs.lastUsed == rhs.lastUsed
}
