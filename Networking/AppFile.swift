//
//  File.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import NotifyingCollection
import Model

public final class AppFile: Copyable, CustomStringConvertible, Hashable, UpdateInPlace
{
	public private(set) var model: File
	public var fileId: Int { return model.id }
	public var wspaceId: Int { return model.wspaceId }
	public var name: String { return model.name }
	public var version: Int { return model.version }
	public var fileSize: Int { return model.fileSize }
	public var dateCreated: Date { return model.dateCreated }
	public var lastModified: Date { return model.lastModified }
	public var fileType: FileType
	
	static var dateFormatter: ISO8601DateFormatter = {
		var df = ISO8601DateFormatter()
		df.formatOptions = [.withInternetDateTime]
		return df
	}()
	
	public init(model: File) throws {
		self.model = model
		guard let ft = FileType.fileType(forFileName: model.name) else {
			throw NetworkingError.unsupportedFileType
		}
		fileType = ft
	}
	
	//documentation inherited from protocol
	public init(instance: AppFile) {
		model = instance.model
		fileType = instance.fileType
	}
	
	public var hashValue: Int { return ObjectIdentifier(self).hashValue }
	
	public var eTag: String { return "f/\(fileId)/\(version)" }
	
	/// returns the file name w/o a file extension
	public var baseName: String {
		guard let idx = name.range(of: ".", options: .backwards) else { return name }
		return String(name[idx.upperBound...])
	}
	
	/// Updates the file to match the current information
	///
	/// - Parameter to: latest information from the server
	/// - Throws: any json parsing errors
	public func update(to model: File) throws {
		assert(fileId == model.id)
		guard let ft = FileType.fileType(forFileName: model.name) else {
			throw NetworkingError.unsupportedFileType
		}
		self.model = model
		fileType = ft
	}

	public var description: String {
		return "<File: \(name) (\(fileId) v\(version))>"
	}
	
	public static func == (a: AppFile, b: AppFile) -> Bool {
		return a.fileId == b.fileId && a.version == b.version
	}
}