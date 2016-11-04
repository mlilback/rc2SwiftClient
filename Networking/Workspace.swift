//
//  Workspace.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Freddy
import ReactiveSwift
import Result
#if os(OSX)
	import AppKit
#else
	import UIKit
#endif


public final class Workspace: JSONDecodable, CustomStringConvertible {
	let wspaceId: Int
	let projectId: Int
	let uniqueId: String
	fileprivate(set) var name: String = ""
	fileprivate(set) var version: Int = 0
	var files: [File] { return _files }
	let fileChangeSignal: Signal<[FileChange], NoError>
	
	private var _files: [File] = []
	private let _fileChangeObserver: Observer<[FileChange], NoError>
	
	public init(json: JSON) throws {
		wspaceId = try json.getInt(at: "id")
		projectId = try json.getInt(at: "projectId")
		uniqueId = try json.getString(at: "uniqueId")
		//these two sets are repeated in update()
		version = try json.getInt(at: "version")
		name = try json.getString(at: "name")
		_files = try json.decodedArray(at: "files")
		let (signal, observer) = Signal<[FileChange], NoError>.pipe()
		fileChangeSignal = signal
		_fileChangeObserver = observer
	}
	
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

	/// Updates the workspace and files
	///
	/// - Parameter json: the updated workspace json
	/// - Throws: json parsing errors
	internal func update(json: JSON) throws {
		name = try json.getString(at: "name")
		version = try json.getInt(at: "version")
		var changes = [FileChange]()
		let fileJsonArray = try json.getArray(at: "files")
		var idsToRemove = Set<Int>(_files.map { $0.fileId })
		try fileJsonArray.forEach { (fileJson) in
			let fid = try fileJson.getInt(at: "id")
			guard let file = file(withId: fid) else {
				//a new file to add
				let newFile = try File(json: fileJson)
				_files.append(newFile)
				changes.append(FileChange(insert: newFile, at: _files.count - 1))
				return
			}
			//a file to update
			try file.update(json: fileJson)
			idsToRemove.remove(fid)
			changes.append(FileChange(update: file))
		}
		//all files have been inserted or updated, just need to remove remaining
		for fileId in idsToRemove {
			let oldFile = self.file(withId: fileId)!
			let fileIdx = _files.index(of: oldFile)!
			changes.append(FileChange(remove: oldFile, at: fileIdx))
			_files.remove(at: fileIdx)
		}
		_fileChangeObserver.send(value: changes)
	}
	
	/// Encapsulates a change in the workspace's file array
	public struct FileChange {
		/// - insert: file was inserted at index
		/// - remove: file was removed from index
		/// - update: 1+ file properties have changed
		enum ChangeType { case insert, remove, update }
		let changeType: ChangeType
		let file: File
		let index: Int
		
		init(insert: File, at: Int) {
			changeType = .insert
			file = insert
			index = at
		}
		
		init(remove: File, at: Int) {
			changeType = .remove
			file = remove
			index = at
		}
		
		init(update: File) {
			changeType = .update
			file = update
			index = -1
		}
	}
}
