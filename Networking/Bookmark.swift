//
//  Bookmark.swift
//  Rc2Client
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import ClientCore
import Model

/// represents a bookmark to an rc2 server
/// project/workspace names are for display purposes and fallback if the workspaceIdentifier is no longer valid
public struct Bookmark: Codable, CustomStringConvertible, CustomDebugStringConvertible, Comparable
{
	public static var defaultBookmark: Bookmark {
		return Bookmark(name: NetworkConstants.defaultBookmarkName, server: nil, workspaceIdent: WorkspaceIdentifier(projectId: 0, wspaceId: 0), project: NetworkConstants.defaultProjectName, workspace: NetworkConstants.defaultWorkspaceName)
	}
	
	public let name: String?
	public let server: ServerHost?
	public let workspaceIdent: WorkspaceIdentifier
	public let projectName: String?
	public let workspaceName: String?
	var lastUsed: TimeInterval
	
	fileprivate init(name: String?, server: ServerHost?, workspaceIdent: WorkspaceIdentifier, project: String?, workspace: String?, lastUsed: TimeInterval = NSDate.distantPast.timeIntervalSinceReferenceDate)
	{
		self.workspaceIdent = workspaceIdent
		self.name = name
		self.server = server
		self.projectName = project
		self.workspaceName = workspace
		self.lastUsed = lastUsed
	}
	
	public init(connectionInfo: ConnectionInfo, workspace: Model.Workspace, name: String? = nil, lastUsed: TimeInterval = 0) {
		//don't save host if localhost
		var host: ServerHost? = connectionInfo.host
		if host == ServerHost.localHost { host = nil }
		self.server = host
		self.name = name
		workspaceIdent = WorkspaceIdentifier(workspace)!
		self.lastUsed = lastUsed
		self.workspaceName = workspace.name
		// swiftlint:disable force_try
		self.projectName = try! connectionInfo.project(withId: workspaceIdent.projectId).name
	}
	
	public func withChangedName(_ newName: String) -> Bookmark {
		return Bookmark(name: newName, server: server, workspaceIdent: workspaceIdent, project: projectName, workspace: workspaceName, lastUsed: lastUsed)
	}
	
	public var description: String { return "" }
	public var debugDescription: String { return "<Bookmark: \(name ?? "unnamed") \(workspaceIdent)>" }
	
	public static func == (lhs: Bookmark, rhs: Bookmark) -> Bool {
		return lhs.name == rhs.name && lhs.server == rhs.server && lhs.projectName == rhs.projectName && lhs.workspaceName == rhs.workspaceName && lhs.lastUsed == rhs.lastUsed
	}
	
	public static func < (lhs: Bookmark, rhs: Bookmark) -> Bool {
		let lname = lhs.name ?? lhs.description
		let rname = rhs.name ?? rhs.description
		if lname == rname { return lhs.lastUsed < rhs.lastUsed }
		return lname < rname
	}
}
