//
//  Workspace.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Freddy
import ReactiveSwift
import Result
import NotifyingCollection
import ClientCore
import os
#if os(OSX)
	import AppKit
#else
	import UIKit
#endif


public final class Workspace: JSONDecodable, Copyable, UpdateInPlace, CustomStringConvertible, Hashable {
	public typealias UElement = Workspace

	typealias FileChange = CollectionChange<File>

	public let wspaceId: Int
	public let projectId: Int
	public let uniqueId: String
	public fileprivate(set) var name: String = ""
	public fileprivate(set) var version: Int = 0
	fileprivate let _files = CollectionNotifier<File>()
	
	public var files: [File] { return _files.values }
	public var fileChangeSignal: Signal<[CollectionChange<File>], NoError> { return _files.changeSignal }
	
	//documentation inherited from protocol
	public init(json: JSON) throws {
		do {
			wspaceId = try json.getInt(at: "id")
			projectId = try json.getInt(at: "projectId")
			uniqueId = try json.getString(at: "uniqueId")
			//these two sets are repeated in update()
			version = try json.getInt(at: "version")
			name = try json.getString(at: "name")
			try _files.append(contentsOf: try json.decodedArray(at: "files"))
		} catch {
			throw Rc2Error(type: .invalidJson, nested: error)
		}
	}

	//documentation inherited from protocol
	public init(instance other: Workspace) {
		wspaceId = other.wspaceId
		projectId = other.projectId
		uniqueId = other.uniqueId
		name = other.name
		version = other.version
		// can force because they must be valid since they come from another workspace
		try! _files.append(contentsOf: other.files)
	}
	
	//documentation inherited from protocol
	public var hashValue: Int { return ObjectIdentifier(self).hashValue }
	
	/// Get a file with a specific fileId
	///
	/// - Parameter withId: the id of the file to find
	/// - Returns: the file with the specified id, or nil
	public func file(withId: Int) -> File? {
		guard let idx =  _files.index(where: { $0.fileId == withId }) else {
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
	public func remove(file: File) throws {
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
	public func update(to other: Workspace) throws {
		assert(wspaceId == other.wspaceId)
		_files.startGroupingChanges()
		defer { _files.stopGroupingChanges() }
		name = other.name
		version = other.version
		var filesToRemove = Set<File>(_files.values)
		var filesToAdd = [File]()
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
				try _files.update(at: idx, to: aFile)
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
	public func imported(file: File) throws -> File {
		guard self.file(withId: file.fileId) == nil else {
			throw Rc2Error(type: .updateFailed, explanation: "attempt to import existing file \(file.name) to workspace \(name)")
		}
		do {
			try _files.append(file)
		} catch {
			throw Rc2Error(type: .updateFailed, nested: error)
		}
		return self.file(withId: file.fileId)!
	}
	
	/// Updates a specific file, sending a change notification
	///
	/// - Parameters:
	///   - fileId: the id of the file to update
	///   - other: the version to update to
	/// - Throws: Rc2Error.noSuchElement if not an element of the file collection, .updatFailed
	public func update(fileId: Int, to other: File) throws {
		guard let ourFile = file(withId: fileId), let fileIdx = _files.index(of: ourFile) else {
			throw Rc2Error(type: .noSuchElement)
		}
		do {
			try _files.update(at: fileIdx, to: other)
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
	public func update(file: File, to other: File) throws {
		guard let fileIdx = _files.index(of: file) else {
			throw Rc2Error(type: .noSuchElement)
		}
		do {
			try _files.update(at: fileIdx, to: other)
		} catch {
			throw Rc2Error(type: .updateFailed, nested: error)
		}
		
	}
	
	/// called to update with a change from the network
	///
	/// - Parameters:
	///   - file: the file sent from the server
	///   - change: the type of change it represents
	internal func update(file: File, change: FileChangeType) {
		let ourFile = self.file(withId: file.fileId)
		switch(change) {
		case .Update:
			guard let ofile = ourFile else {
				os_log("got file change update w/o a known file")
				return
			}
			guard let _ = try? update(file: ofile, to: file) else {
				os_log("file change update failed"); return
			}
		case .Insert:
			guard let _ = try? _files.append(file) else {
				os_log("file change insert failed"); return
			}
		case .Delete:
			guard let _ = try? _files.remove(ourFile!) else {
				os_log("file change delete failed"); return
			}
		}
	}
	
	public static func == (lhs: Workspace, rhs: Workspace) -> Bool {
		return lhs.wspaceId == rhs.wspaceId && lhs.version == rhs.version && lhs.hashValue == rhs.hashValue
	}
}