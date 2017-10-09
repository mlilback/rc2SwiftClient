//
//  Workspace.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import ReactiveSwift
import Result
import ClientCore
import os
import Model

// removed UpdateInPlace, Copyable since that behavior is indefined with new model
public final class AppWorkspace: CustomStringConvertible, Hashable
{
//	public typealias UElement = AppWorkspace

	public enum FileChangeType: String {
		case add, modify, remove
		
	}
	public struct FileChange {
		public let type: FileChangeType
		public let file: AppFile
	}
	
//	typealias FileChange = CollectionChange<AppFile>

	public var identifier: WorkspaceIdentifier { return WorkspaceIdentifier(projectId: model.projectId, wspaceId: model.id) }
	
	public private(set) var model: Workspace
	
	public var wspaceId: Int { return model.id }
	public var projectId: Int { return model.projectId }
	public var uniqueId: String { return model.uniqueId }
	public var name: String { return model.name }
	public var version: Int { return model.version }
	
	fileprivate let _files = MutableProperty<[AppFile]>([])
	/// changes to should be monitored via fileChangeSignal. order is undefined and can change when signal is fired
	public var files: [AppFile] { return _files.value }

	public let fileChangeSignal: Signal<[FileChange], NoError> // { return _files.changeSignal }
	private let fileChangeObserver: Signal<[FileChange], NoError>.Observer
	
	public init(model: Workspace, files rawFiles: [AppFile]) throws {
		self.model = model
		_files.value = rawFiles
		(fileChangeSignal, fileChangeObserver) = Signal<[FileChange], NoError>.pipe()
	}

	//documentation inherited from protocol
	public var hashValue: Int { return ObjectIdentifier(self).hashValue }
	
	/// Get a file with a specific fileId
	///
	/// - Parameter withId: the id of the file to find
	/// - Returns: the file with the specified id, or nil
	public func file(withId: Int) -> AppFile? {
		guard let idx = _files.value.index(where: { $0.fileId == withId }) else {
			return nil
		}
		return _files.value[idx]
	}
	
	/// Get a file with a specific name
	///
	/// - Parameter withName: the name of the file to find
	/// - Returns: the matching file or nil
	public func file(withName: String) -> AppFile? {
		guard let idx = _files.value.index(where: { $0.name.caseInsensitiveCompare(withName) == .orderedSame }) else { return nil }
		return _files.value[idx]
	}
	
	public var description: String {
		return "<Workspace: \(name) (\(wspaceId))"
	}

	/// Returns a signal producer that will wait until an AppFile exists in this workspace with a timeout
	///
	/// - Parameter fileId: the id of the file to look for
	/// - Parameter timeout: how long to wait for the file to appear
	/// - Returns: a producer that will return the requested file or an error if timeout elapses
	public func whenFileExists(fileId: Int, within timeout: TimeInterval) -> SignalProducer<AppFile, Rc2Error>
	{
		if let file = file(withId: fileId) {
			return SignalProducer<AppFile, Rc2Error>(value: file)
		}
		let sig = fileChangeSignal
			.promoteError(Rc2Error.self)
			.filterMap({ changes in changes.first(where: { $0.type == .add && $0.file.fileId == fileId }) })
			.map( { $0.file })
			.timeout(after: timeout, raising: Rc2Error(type: .timeout), on: QueueScheduler.main)
		return SignalProducer<AppFile, Rc2Error>(sig)
	}

	/// Returns a signal producer that will wait until an AppFile exists in this workspace with a timeout
	///
	/// - Parameter fileIds: the ids of the files to look for
	/// - Parameter timeout: how long to wait for the files to appear
	/// - Returns: a producer that will return the requested files or an error if timeout elapses
	public func whenFilesExist(withIds fileIds: [Int], within timeout: TimeInterval) -> SignalProducer<[AppFile], Rc2Error>
	{
		// should make 1 global timeout for all of them, but shouldn't really make a difference
		let matchingFiles = _files.value.filter({ fileIds.contains($0.fileId) })
		if matchingFiles.count == fileIds.count {
			return SignalProducer<[AppFile], Rc2Error>(value: matchingFiles)
		}
		let producers = fileIds.map { whenFileExists(fileId: $0, within: timeout) }
		return SignalProducer< SignalProducer<AppFile, Rc2Error>, Rc2Error >(producers)
			.flatten(.concat)
			.collect()
	}

	/// Updates the workspace and files
	///
	/// - Parameter to: workspace to copy all updateable data from
	/// - Throws: Rc2Error.updateFailed
	internal func update(with info: SessionResponse.InfoData) throws {
		assert(model.id == info.workspace.id)
		model = info.workspace
		var changes = [FileChange]()
		defer { if changes.count > 0 { fileChangeObserver.send(value: changes) } }
		var myFiles = Set<AppFile>(_files.value)
		var filesToRemove = myFiles
		var filesToAdd = [File]()
		// split myFiles into fileToRemove, filesToAdd, or updates AppFile in myFiles
		for rawFile in info.files {
			guard let existingFile = myFiles.first(where: { $0.model.id == rawFile.id }) else {
				filesToAdd.append(rawFile) //rawFile is new
				continue
			}
			try existingFile.update(to: rawFile)
			filesToRemove.remove(existingFile)
			changes.append(FileChange(type: .modify, file: existingFile))
		}
		// remove from myFiles any AppFiles that weren't in info.files
		filesToRemove.forEach {
			changes.append(FileChange(type: .remove, file: $0))
			myFiles.remove($0)
		}
		// add to myFiles any new Files that were in info.files
		try filesToAdd.forEach {
			let newFile = try AppFile(model: $0)
			changes.append(FileChange(type: .add, file: newFile))
			myFiles.insert(newFile)
		}
		// atomically apply files changes (from set as order doesn't matter)
		_files.value = [AppFile](myFiles)
		fileChangeObserver.send(value: changes)
	}
	
	/// Adds file to the workspace
	///
	/// - Parameter file: a file sent from the server in response to an upload
	/// - Returns: the file that was copied and inserted into the file array
	/// - Throws: Rc2Error.updateFailed
//	@discardableResult
//	public func imported(file: File) throws -> AppFile {
//		guard self.file(withId: file.id) == nil, let newFile = try? AppFile(model: file) else {
//			throw Rc2Error(type: .updateFailed, explanation: "attempt to import existing file \(file.name) to workspace \(name)")
//		}
//		do {
//			try _files.append(newFile)
//		} catch {
//			throw Rc2Error(type: .updateFailed, nested: error)
//		}
//		return newFile
//	}
	
	/// Updates a specific file based on the server change struct
	///
	/// - Parameters:
	///   - change: the change info from the server
	/// - Throws: .noSuchElement or nested error from calling .update on the AppFile
	public func update(change: SessionResponse.FileChangedData) throws {
		os_log("update file %d to other called", log: .model, type: .debug, change.fileId)
		switch change.changeType {
		case .insert:
			guard let modelFile = change.file else { fatalError("insert should always have a file") }
			let newFile = try AppFile(model: modelFile)
			_files.value.append(newFile)
			fileChangeObserver.send(value: [FileChange(type: .add, file: newFile)])
		case .update:
			guard let ourFile = file(withId: change.fileId),
				let updatedFile = change.file
				else { throw Rc2Error(type: .noSuchElement) }
			try ourFile.update(to: updatedFile)
		case .delete:
			//need to remove from _files and send change notification
			guard let ourFile = file(withId: change.fileId) else {
				os_log("delete change for non-existant file %d", log: .model, change.fileId)
				throw Rc2Error(type: .updateFailed)
			}
			//can force because guard above says it must exist
			_files.value.remove(at: _files.value.index(of: ourFile)!)
			fileChangeObserver.send(value: [FileChange(type: .remove, file: ourFile)])
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
