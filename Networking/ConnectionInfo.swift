//
//  ConnectionInfo.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Freddy
import NotifyingCollection

/// Encapsulates the host and properties returned from a login request
public struct ConnectionInfo: CustomStringConvertible {
	let host: ServerHost
	let user: User
	let authToken: String
	var projects: [Project]
	
	let _projects = CollectionNotifier<Project>()
	
	/// initializer
	///
	/// - Parameters:
	///   - host: the host connected to
	///   - json: the json returned when connecting
	/// - Throws: json decoding exceptions
	public init(host: ServerHost, json: JSON) throws {
		self.host = host
		authToken = try json.getString(at: "token")
		user = try json.decode(at: "user")
		projects = try json.decodedArray(at: "projects")
	}
	
	//documentation inherited from protocol
	public var description: String {
		return "<LoginSession: \(user.login)@\(host.name)>"
	}

	/// find a project by id
	///
	/// - Parameter projectId: the id to search for
	/// - Returns: the matching project or nil if not found
	public func project(withId projectId: Int) -> Project? {
		return projects.filter({ $0.projectId == projectId }).first
	}
	
	/// find a project by name
	///
	/// - Parameter withName: the name to search for
	/// - Returns: the matching project or nil if not found
	public func project(withName name: String) -> Project? {
		return projects.filter({ $0.name == name }).first
	}
}
