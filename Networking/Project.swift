//
//  Project.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Freddy
import ReactiveSwift
import Result
import NotifyingCollection

public final class Project: JSONDecodable, Copyable, UpdateInPlace, CustomStringConvertible, Hashable
{
	let projectId: Int
	let userId: Int
	public fileprivate(set) var name: String
	public fileprivate(set) var version: Int
	var workspaces: [Workspace] { return _workspaces.values }
	var workspaceChangeSignal: Signal<[CollectionChange<Workspace>], NoError> { return _workspaces.changeSignal }

	private var _workspaces = NestingCollectionNotifier<Workspace>()

	//documentation inherited from protocol
	public init(json: JSON) throws {
		projectId = try json.getInt(at: "id")
		userId = try json.getInt(at: "userId")
		version = try json.getInt(at: "version")
		name = try json.getString(at: "name")
		let wspaces = try json.decodedArray(at: "workspaces", type: Workspace.self)
		try _workspaces.append(contentsOf: wspaces)
	}

	//documentation inherited from protocol
	public init(instance other: Project) {
		projectId = other.projectId
		userId = other.userId
		name = other.name
		version = other.version
		//can force because they are from another copy so must be valid
		try! _workspaces.append(contentsOf: other.workspaces)
	}
	
	//documentation inherited from protocol
	public var description: String {
		return "<Project \(name) (\(projectId))"
	}
	
	//documentation inherited from protocol
	public var hashValue: Int { return ObjectIdentifier(self).hashValue }

	/// searches for a workspace with the specified id
	/// - Parameter withId: the id to look for
	/// - returns: a matching workspace or nil if not found
	public func workspace(withId: Int) -> Workspace? {
		guard let idx =  _workspaces.index(where: { $0.wspaceId == withId }) else {
			return nil
		}
		return _workspaces[idx]
	}
	
	//documentation inherited from protocol
	public func update(to other: Project) throws {
		print("vers=\(other.workspaces[0].files[0].version)")
		assert(projectId == other.projectId)
		assert(version <= other.version) //TODO: verify the server actually increments this if a file changes
		assert(userId == other.userId)
		name = other.name
		version = other.version
		_workspaces.startGroupingChanges()
		defer { _workspaces.stopGroupingChanges() }
		var wspacesToRemove = Set<Workspace>(_workspaces)
		var wspacesToAdd = [Workspace]()
		try other.workspaces.forEach { (aWspace) in
			guard let wspace = workspace(withId: aWspace.wspaceId) else {
				//a new workspace to add
				wspacesToAdd.append(aWspace.copy())
				return
			}
			//a file to update
			//force is ok because we know it is there since we just found it via workspace(withId:)
			let idx = _workspaces.index(of: wspace)!
			try _workspaces.update(at: idx, to: aWspace)
			wspacesToRemove.remove(wspace)
		}
		try _workspaces.append(contentsOf: wspacesToAdd)
		//all files have been inserted or updated, just need to remove remaining
		try wspacesToRemove.forEach { (aWspace) in try _workspaces.remove(aWspace) }
	}
	
	public func addWorkspaceObserver(identifier: String, observer: @escaping (Workspace) -> Disposable?) {
		_workspaces.observe(identifier: identifier, observer: observer)
	}
	
	public func removeObWorkspaceOserver(identifier: String) {
		_workspaces.removeObserver(identifier: identifier)
	}

	public static func == (lhs: Project, rhs: Project) -> Bool {
		return lhs.projectId == rhs.projectId && lhs.version == rhs.version
	}
}
