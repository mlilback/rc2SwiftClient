//
//  ConnectionInfo.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Freddy
import NotifyingCollection
import ReactiveSwift
import Result

/// Encapsulates the host and properties returned from a login request
public class ConnectionInfo: CustomStringConvertible {
	public let host: ServerHost
	public let user: User
	public let authToken: String
	public var projects: [Project] { return _projects.values }
	public var projectChangeSignal: Signal<[CollectionChange<Project>], NoError> { return _projects.changeSignal }
	
	private let _projects = CollectionNotifier<Project>()
	
	public var urlSessionConfig: URLSessionConfiguration!
	
	public var defaultProject: Project? { return project(withName: NetworkConstants.defaultProjectName) }
	
	/// initializer
	///
	/// - Parameters:
	///   - host: the host connected to
	///   - json: the json returned when connecting
	///   - config: defaults to the .default configuration
	/// - Throws: json decoding exceptions
	public init(host: ServerHost, json: JSON, config: URLSessionConfiguration = .default) throws {
		self.host = host
		authToken = try json.getString(at: "token")
		user = try json.decode(at: "user")
		try _projects.append(contentsOf: try json.decodedArray(at: "projects"))
		config.httpAdditionalHeaders = ["Rc2-Auth": authToken]
		self.urlSessionConfig = config
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
		return projects.first(where: { $0.projectId == projectId })
	}
	
	/// find a project by name
	///
	/// - Parameter withName: the name to search for
	/// - Returns: the matching project or nil if not found
	public func project(withName name: String) -> Project? {
		return projects.first(where: { $0.name == name })
	}
}
