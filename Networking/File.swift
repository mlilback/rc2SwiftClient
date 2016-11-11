//
//  File.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Freddy
import NotifyingCollection

public final class File: JSONDecodable,Copyable, CustomStringConvertible, Hashable, UpdateInPlace
{
	let fileId : Int
	fileprivate(set) var name : String!
	fileprivate(set) var version : Int!
	fileprivate(set) var fileSize : Int!
	fileprivate(set) var dateCreated : Date!
	fileprivate(set) var lastModified : Date!
	fileprivate(set) var fileType: FileType!
	
	public init(json:JSON) throws {
		fileId = try json.getInt(at: "id")
		try applyJson(json: json)
	}
	
	//documentation inherited from protocol
	public init(instance: File) {
		fileId = instance.fileId
		name = instance.name
		version = instance.version
		fileSize = instance.fileSize
		dateCreated = instance.dateCreated
		lastModified = instance.lastModified
		fileType = instance.fileType
	}
	
	public var hashValue: Int { return ObjectIdentifier(self).hashValue }
	
	///initialize with native dictionary from a MessagePackDictionary
//	init(dict:[String:AnyObject]) {
//		let json = JSON(
//		fileId = dict["id"] as! Int
//		name = dict["name"] as! String
//		version = dict["version"] as! Int
//		fileSize = dict["fileSize"] as! Int!
//		dateCreated = Date(timeIntervalSince1970: (dict["dateCreated"] as! Double)/1000.0)
//		lastModified = Date(timeIntervalSince1970: (dict["lastModified"] as! Double)/1000.0)
//		if let ft = FileType.fileTypeWithExtension((name as NSString).pathExtension) {
//			self.fileType = ft
//		} else {
//			assertionFailure("invalid file type")
//			//compiler won't let the property not be set, even though we're exiting the program
//			self.fileType = FileType.allFileTypes.first!
//		}
//	}
	
	/// Updates the file to match the current information
	///
	/// - Parameter json: latest information from the server
	/// - Throws: any json parsing errors
	public func update(to other: File) throws {
		assert(fileId == other.fileId)
		name = other.name
		version = other.version
		fileSize = other.fileSize
		dateCreated = other.dateCreated
		lastModified = other.lastModified
		fileType = other.fileType
	}

	public var description : String {
		return "<File: \(name) (\(fileId) v\(version))>";
	}
	
	public static func ==(a: File, b: File) -> Bool {
		return a.fileId == b.fileId && a.version == b.version;
	}
}

extension File {
	fileprivate func applyJson(json: JSON) throws {
		let fileName = try json.getString(at: "name")
		guard let ft = FileType.fileType(forFileName: fileName) else {
			throw NetworkingError.unsupportedFileType
		}
		name = fileName
		fileType = ft

		version = try json.getInt(at: "version")
		fileSize = try json.getInt(at: "fileSize")
		dateCreated = Date(timeIntervalSince1970: try json.getDouble(at: "dateCreated") / 1000.0)
		lastModified = Date(timeIntervalSince1970: try json.getDouble(at: "lastModified") / 1000.0)
	}
}
