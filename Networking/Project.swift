//
//  Project.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Freddy
import ReactiveSwift

public final class Project: JSONDecodable, CustomStringConvertible, Equatable {
	let projectId: Int
	let userId: Int
	let name: String
	let version: Int
	let workspaces: MutableProperty<String>
	
	public init(json: JSON) throws {
		projectId = try json.getInt(at: "id")
		userId = try json.getInt(at: "userId")
		version = try json.getInt(at: "version")
		name = try json.getString(at: "name")
		workspaces = MutableProperty<String>("foo")
	}
	
	public var description: String {
		return "<Project \(name) (\(projectId))"
	}
	
	public static func == (lhs: Project, rhs: Project) -> Bool {
		return lhs.projectId == rhs.projectId && lhs.version == rhs.version
	}
}
