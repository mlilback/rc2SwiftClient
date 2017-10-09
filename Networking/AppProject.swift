//
//  Project.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import ReactiveSwift
import Result
import Model

public final class AppProject: CustomStringConvertible, Hashable
{
	public private(set) var model: Project
	public var projectId: Int { return model.id }
	public var userId: Int { return model.userId }
	public var name: String { return model.name }
	public var version: Int { return model.version }

	public let workspaces: Property<[AppWorkspace]>
	private let _workspaces: MutableProperty<[AppWorkspace]>

	public init(model: Project, workspaces rawWorkspaces: [AppWorkspace]) throws {
		self.model = model
		self._workspaces = MutableProperty<[AppWorkspace]>(rawWorkspaces)
		self.workspaces = Property<[AppWorkspace]>(_workspaces)
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
	public func workspace(withId: Int) -> AppWorkspace? {
		guard let idx = _workspaces.value.index(where: { $0.wspaceId == withId }) else {
			return nil
		}
		return _workspaces.value[idx]
	}
	
	/// searches for a workspace with the specified name
	/// - Parameter withName: the name to look for
	/// - returns: a matching workspace or nil if not found
	public func workspace(withName: String) -> AppWorkspace? {
		guard let idx = _workspaces.value.index(where: { $0.name == withName }) else {
			return nil
		}
		return _workspaces.value[idx]
	}
	
	internal func update(model: Project, workspaces: [AppWorkspace]) {
		self.model = model
		self._workspaces.value = workspaces
	}
	
//	//documentation inherited from protocol
//	public func update(to other: AppProject) throws {
//		// MODEL: fix me, broken
//		assert(projectId == other.projectId)
//		assert(version <= other.version)
//		assert(userId == other.userId)
//		model = other.model
//		_workspaces.startGroupingChanges()
//		defer { _workspaces.stopGroupingChanges() }
//		var wspacesToRemove = Set<AppWorkspace>(_workspaces)
//		var wspacesToAdd = [AppWorkspace]()
//		try other.workspaces.forEach { (aWspace) in
//			guard let wspace = workspace(withId: aWspace.wspaceId) else {
//				//a new workspace to add
//				wspacesToAdd.append(aWspace.copy())
//				return
//			}
//			//a file to update
//			//force is ok because we know it is there since we just found it via workspace(withId:)
//			let idx = _workspaces.index(of: wspace)!
//			try _workspaces.update(at: idx, to: aWspace)
//			wspacesToRemove.remove(wspace)
//		}
//		try _workspaces.append(contentsOf: wspacesToAdd)
//		//all files have been inserted or updated, just need to remove remaining
//		try wspacesToRemove.forEach { (aWspace) in try _workspaces.remove(aWspace) }
//	}
	
//	/// adds a workspace to the array of workspaces
//	///
//	/// - Parameter workspace: workspace that was added
//	/// - Throws: Rc2Error
//	internal func added(workspace: AppWorkspace) throws {
//		try _workspaces.append(workspace)
//	}
//
//	public func addWorkspaceObserver(identifier: String, observer: @escaping (AppWorkspace) -> Disposable?) {
//		_workspaces.observe(identifier: identifier, observer: observer)
//	}
//
//	public func removeObWorkspaceOserver(identifier: String) {
//		_workspaces.removeObserver(identifier: identifier)
//	}

	public static func == (lhs: AppProject, rhs: AppProject) -> Bool {
		return lhs.projectId == rhs.projectId && lhs.version == rhs.version
	}
}
