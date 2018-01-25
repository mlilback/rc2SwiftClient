//
//  ConnectionInfo.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Freddy
import ReactiveSwift
import Result
import Model
import MJLLogger

/// Encapsulates the host and properties returned from a login request
public class ConnectionInfo: CustomStringConvertible {
	private var bulkInfo: BulkUserInfo!
	public let host: ServerHost
	public var user: Model.User { return bulkInfo.user }
	public let authToken: String
	/// It is only possible to monitor the entire array. No signals are sent if an individual project is changed, therefore references to projects are fragile. They might become invalid and not know it. Always lookup the project, do not store it.
	public let projects: Property<Set<AppProject>>
	// private editable version that projects monitors
	private let _projects: MutableProperty<Set<AppProject>>
	private let encoder: JSONEncoder
	private let decoder: JSONDecoder
	
	public var urlSessionConfig: URLSessionConfiguration!
	
	public var defaultProject: AppProject? { return project(withName: NetworkConstants.defaultProjectName) }
	
	public enum Errors: Error {
		case notFound
	}
	
	/// initializer
	///
	/// - Parameters:
	///   - host: the host connected to
	///   - json: the json returned when connecting
	///   - config: defaults to the .default configuration
	/// - Throws: json decoding exceptions
	public init(host: ServerHost, bulkInfoData: Data, authToken: String, config: URLSessionConfiguration = .default) throws
	{
		encoder = JSONEncoder()
		encoder.dataEncodingStrategy = .base64
		encoder.dateEncodingStrategy = .secondsSince1970
		encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "Inf", negativeInfinity: "-Inf", nan: "NaN")
		decoder = JSONDecoder()
		decoder.dataDecodingStrategy = .base64
		decoder.dateDecodingStrategy = .secondsSince1970
		decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "Inf", negativeInfinity: "-Inf", nan: "NaN")
		
		_projects = MutableProperty< Set<AppProject> >([])
		projects = Property< Set<AppProject> >(_projects)
		
		self.host = host
		self.authToken = authToken
		config.httpAdditionalHeaders = ["Authorization": "Bearer \(authToken)"]
		self.urlSessionConfig = config
		self.bulkInfo = try decoder.decode(BulkUserInfo.self, from: bulkInfoData)
		try load(bulkInfo: bulkInfo)
	}
	
	//documentation inherited from protocol
	public var description: String {
		return "<LoginSession: \(user.login)@\(host.name)>"
	}
	
	/// Encode an object for transmission to the server
	///
	/// - Parameter object: the object to encode
	/// - Returns: the encoded data
	/// - Throws: any errors serializing the object
	public func encode<T: Encodable>(_ object: T) throws -> Data {
		return try encoder.encode(object)
	}
	
	/// Decode an object from data
	///
	/// - Parameter data: the data to decode
	/// - Returns: the decoded object
	/// - Throws: any serialization errors
	public func decode<T: Decodable>(data: Data) throws -> T {
		return try decoder.decode(T.self, from: data)
	}
	
	/// find a project by id
	///
	/// - Parameter projectId: the id to search for
	/// - Returns: the matching project or nil if not found
	/// - Throws: .notFound if no such workspace exists
	public func project(withId projectId: Int) throws -> AppProject {
		guard let proj = _projects.value.first(where: { $0.projectId == projectId })
			else { throw Errors.notFound }
		return proj
	}
	
	/// find a project by name
	///
	/// - Parameter withName: the name to search for
	/// - Returns: the matching project or nil if not found
	public func project(withName name: String) -> AppProject? {
		return _projects.value.first(where: { $0.name == name })
	}
	
	/// get workspaces for a particular project
	///
	/// - Parameter forProject: the project
	/// - Returns: the array of workspaces for the project
	public func workspaces(forProject: AppProject) -> [AppWorkspace]? {
		return forProject.workspaces.value
	}
	
	/// get a particular workspace for a project
	///
	/// - Parameters:
	///   - withId: the id of the workspace
	///   - project: the project the workspace belongs to
	/// - Returns: the requested workspace
	/// - Throws: .notFound if no such workspace exists
	public func workspace(withId: Int, in project: AppProject) throws -> AppWorkspace {
		guard let wspace = project.workspaces.value.first(where: { $0.wspaceId == withId }) else { throw Errors.notFound }
		return wspace
	}
	
	/// returns a workspace for the specified identifier, or nil if no such workspace exists
	///
	/// - Parameter identifier: the workspace identifier to lookup
	/// - Returns: the matching workspace, or nil if no such workspace exists
	public func workspace(withIdentifier identifier: WorkspaceIdentifier) -> AppWorkspace? {
		guard let optWspace = try? project(withId: identifier.projectId).workspace(withId: identifier.wspaceId),
			let wspace = optWspace
			else { return nil }
		return wspace
	}
	
	/// called by other module objects (like RestClient) when the bulkInfo needs to be updated
	///
	/// - Parameter bulkInfo: the updated information
	internal func update(bulkInfo: BulkUserInfo) {
		// TODO: implement
		
	}
	
	private func updateProjects(bulkInfo: BulkUserInfo) {
		
	}
	
	/// updates the AppWorkspace with the update
	internal func update(sessionInfo: SessionResponse.InfoData) {
		guard let project = try? project(withId: sessionInfo.workspace.projectId),
			let existingWspace = try? workspace(withId: sessionInfo.workspace.id, in: project)
		else { return }
		do {
			try existingWspace.update(with: sessionInfo)
		} catch {
			Log.error("error updating workspace: \(error)", .app)
		}
	}
	
	// load the bulk info
	private func load(bulkInfo: BulkUserInfo) throws {
		assert(_projects.value.count == 0) //FIXME: Need to update instead of create if already exists
		var tmpProjects = Set<AppProject>()
		for rawProject in bulkInfo.projects {
			let wspaces = (bulkInfo.workspaces[rawProject.id] ?? []).map { create(workspace: $0, bulkInfo: bulkInfo) }
			tmpProjects.insert(AppProject(model: rawProject, workspaces: wspaces))
		}
		_projects.value = tmpProjects
	}

	/// creates AppFiles based on Files in bulkInfo, then creates the AppWorkspace
	private func create(workspace: Workspace, bulkInfo: BulkUserInfo) -> AppWorkspace {
		let rawFiles = bulkInfo.files[workspace.id] ?? []
		//only error is if unsupported filetype. that should never happen. if it does, just ignore that file
		let files: [AppFile] = rawFiles.flatMap {
			do {
				return try AppFile(model: $0)
			} catch {
				Log.warn("failed to create appfile \($0.id). skipping", .model)
				return nil
			}
		}
		return AppWorkspace(model: workspace, files: files)
	}
	
}
