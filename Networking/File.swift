//
//  File.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Freddy
import NotifyingCollection

public final class File: JSONDecodable, JSONEncodable, Copyable, CustomStringConvertible, Hashable, UpdateInPlace
{
	public let fileId : Int
	public let wspaceId: Int
	public fileprivate(set) var name : String
	public fileprivate(set) var version : Int
	public fileprivate(set) var fileSize : Int
	public fileprivate(set) var dateCreated : Date
	public fileprivate(set) var lastModified : Date
	public fileprivate(set) var fileType: FileType
	
	static var dateFormatter: ISO8601DateFormatter = {
		var df = ISO8601DateFormatter()
		df.formatOptions = [.withInternetDateTime]
		return df
	}()
	
	public init(json:JSON) throws {
		fileId = try json.getInt(at: "id")
		wspaceId = try json.getInt(at: "wspaceId")
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
	
	//documentation inherited from protocol
	public init(instance: File) {
		fileId = instance.fileId
		wspaceId = instance.wspaceId
		name = instance.name
		version = instance.version
		fileSize = instance.fileSize
		dateCreated = instance.dateCreated
		lastModified = instance.lastModified
		fileType = instance.fileType
	}
	
	public var hashValue: Int { return ObjectIdentifier(self).hashValue }
	
	public var eTag: String { return "f/\(fileId)/\(version)" }
	
	/// returns the file name w/o a file extension
	public var baseName: String {
		guard let idx = name.range(of: ".", options: .backwards) else { return name }
		return name.substring(from: idx.upperBound)
	}
	
	///initialize with native dictionary from a MessagePackDictionary
	//TODO: get rid of force unwraps
	init(dict: [String: AnyObject]) {
		fileId = dict["id"] as! Int
		wspaceId = dict["wspaceId"] as! Int
		name = dict["name"] as! String
		version = dict["version"] as! Int
		fileSize = dict["fileSize"] as! Int!
		dateCreated = Date(timeIntervalSince1970: (dict["dateCreated"] as! Double)/1000.0)
		lastModified = Date(timeIntervalSince1970: (dict["lastModified"] as! Double)/1000.0)
		if let ft = FileType.fileType(forFileName: name) {
			self.fileType = ft
		} else {
			assertionFailure("invalid file type")
			//compiler won't let the property not be set, even though we're exiting the program
			self.fileType = FileType.allFileTypes.first!
		}
	}
	
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
	
	public func toJSON() -> JSON {
		return .dictionary(["id": .int(fileId), "wspaceId": .int(wspaceId), "name": .string(name), "version": .int(version), "fileSize": .int(fileSize), "dateCreated": .string(File.dateFormatter.string(from: dateCreated)), "lastModified": .string(File.dateFormatter.string(from: lastModified))])
	}
	
	public static func ==(a: File, b: File) -> Bool {
		return a.fileId == b.fileId && a.version == b.version;
	}
}
