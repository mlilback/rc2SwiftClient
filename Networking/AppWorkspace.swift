//
//  Workspace.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import ReactiveSwift
import Result
import NotifyingCollection
import ClientCore
import os
import Model

public final class AppWorkspace: Copyable, UpdateInPlace, CustomStringConvertible, Hashable
{
//	public typealias UElement = AppWorkspace

	typealias FileChange = CollectionChange<AppFile>

	public var identifier: WorkspaceIdentifier { return WorkspaceIdentifier(projectId: model.projectId, wspaceId: model.id) }
	
	public private(set) var model: Workspace
	
	public var wspaceId: Int { return model.id }
	public var projectId: Int { return model.projectId }
	public var uniqueId: String { return model.uniqueId }
	public var name: String { return model.name }
	public var version: Int { return model.version }
	fileprivate let _files = CollectionNotifier<AppFile>()
	
	public var files: [AppFile] { return _files.values }
	public var fileChangeSignal: Signal<[CollectionChange<AppFile>], NoError> { return _files.changeSignal }
	
	public init(model: Workspace, files rawFiles: [AppFile]) throws {
		self.model = model
		try _files.append(contentsOf: rawFiles)
	}

	//documentation inherited from protocol
	public init(instance other: AppWorkspace) {
		model = other.model
		// can force because they must be valid since they come from another workspace
		// swiftlint:disable:next force_try
		try! _files.append(contentsOf: other.files)
	}
	
	//documentation inherited from protocol
	public var hashValue: Int { return ObjectIdentifier(self).hashValue }
	
	/// Get a file with a specific fileId
	///
	/// - Parameter withId: the id of the file to find
	/// - Returns: the file with the specified id, or nil
	public func file(withId: Int) -> AppFile? {
		guard let idx = _files.index(where: { $0.fileId == withId }) else {
			return nil
		}
		return _files[idx]
	}
	
	/// Get a file with a specific name
	///
	/// - Parameter withName: the name of the file to find
	/// - Returns: the matching file or nil
	public func file(withName: String) -> AppFile? {
		guard let idx = _files.index(where: { $0.name.caseInsensitiveCompare(withName) == .orderedSame }) else {
			return nil
		}
		return _files[idx]
	}
	
	public var description: String {
		return "<Workspace: \(name) (\(wspaceId))"
	}

	/// removes a file
	///
	/// - Parameter file: file to remove
	/// - Throws: Rc2Error.updateFailed with a CollectionNotifierError
	public func remove(file: AppFile) throws {
		do {
			try _files.remove(file)
		} catch {
			throw Rc2Error(type: .updateFailed, nested: error)
		}
	}
	
	/// Updates the workspace and files
	///
	/// - Parameter to: workspace to copy all updateable data from
	/// - Throws: Rc2Error.updateFailed
	@available(*, deprecated)
	public func update(to other: AppWorkspace) throws {
		// MODEL: this no longer works.
		assert(wspaceId == other.wspaceId)
		model = other.model
		_files.startGroupingChanges()
		defer { _files.stopGroupingChanges() }
		var filesToRemove = Set<AppFile>(_files.values)
		var filesToAdd = [AppFile]()
		do {
			try other.files.forEach { (aFile) in
				guard let file = file(withId: aFile.fileId) else {
					//a new file to add
					filesToAdd.append(aFile.copy())
					return
				}
				//a file to update
				//force is ok because we know it is there since we just found it via workspace(withId:)
				let idx = _files.index(of: file)!
				try _files.update(at: idx, to: aFile.model)
				filesToRemove.remove(file)
			}
			try _files.append(contentsOf: filesToAdd)
			//all files have been inserted or updated, just need to remove remaining
			try filesToRemove.forEach { (aFile) in try _files.remove(aFile) }
		} catch {
			throw Rc2Error(type: .updateFailed, nested: error)
		}
	}
	
	/// Adds file to the workspace
	///
	/// - Parameter file: a file sent from the server in response to an upload
	/// - Returns: the file that was copied and inserted into the file array
	/// - Throws: Rc2Error.updateFailed
	@discardableResult
	public func imported(file: File) throws -> AppFile {
		guard self.file(withId: file.id) == nil, let newFile = try? AppFile(model: file) else {
			throw Rc2Error(type: .updateFailed, explanation: "attempt to import existing file \(file.name) to workspace \(name)")
		}
		do {
			try _files.append(newFile)
		} catch {
			throw Rc2Error(type: .updateFailed, nested: error)
		}
		return newFile
	}
	
	/// Updates a specific file, sending a change notification
	///
	/// - Parameters:
	///   - fileId: the id of the file to update
	///   - other: the version to update to
	/// - Throws: Rc2Error.noSuchElement if not an element of the file collection, .updatFailed
	public func update(change: SessionResponse.FileChangedData) throws {
		os_log("update file %d to other called", log: .model, type: .debug, change.fileId)
		guard let ourFile = file(withId: change.fileId), let fileIdx = _files.index(of: ourFile),
			let updatedFile = change.file
		else {
			throw Rc2Error(type: .noSuchElement)
		}
		do {
			try ourFile.update(to: updatedFile)
			try _files.update(at: fileIdx, to: updatedFile)
		} catch {
			throw Rc2Error(type: .updateFailed, nested: error)
		}
	}

	/// Updates a specific file, sending a change notification
	///
	/// - Parameters:
	///   - file: the file to update
	///   - other: the version to update to
	/// - Throws: .noSuchElement or .updateFailed
	public func update(file: AppFile, to other: File) throws {
		os_log("update file to other called %d", log: .model, type: .debug, file.fileId)
		guard let fileIdx = _files.index(of: file) else {
			throw Rc2Error(type: .noSuchElement)
		}
		do {
			try _files.update(at: fileIdx, to: other)
		} catch {
			throw Rc2Error(type: .updateFailed, nested: error)
		}
		
	}
	
//	/// called to update with a change from the network
//	///
//	/// - Parameters:
//	///   - file: the file sent from the server
//	///   - change: the type of change it represents
//	internal func update(file: AppFile, change: FileChangeType) {
//		os_log("update change to %d", log: .model, type: .debug, file.fileId)
//		let ourFile = self.file(withId: file.fileId)
//		switch change {
//		case .Update:
//			guard let ofile = ourFile else {
//				os_log("got file change update w/o a known file", log: .session)
//				return
//			}
//			guard let _ = try? update(file: ofile, to: file) else {
//				os_log("file change update failed", log: .session); return
//			}
//		case .Insert:
//			if ourFile == file { //already inserted, likely via import
//				return
//			}
//			guard let _ = try? _files.append(file) else {
//				os_log("file change insert failed", log: .session); return
//			}
//		case .Delete:
//			guard let _ = try? _files.remove(ourFile!) else {
//				os_log("file change delete failed", log: .session); return
//			}
//		}
//	}
	
	public static func == (lhs: AppWorkspace, rhs: AppWorkspace) -> Bool {
		return lhs.wspaceId == rhs.wspaceId && lhs.version == rhs.version && lhs.hashValue == rhs.hashValue
	}
}
