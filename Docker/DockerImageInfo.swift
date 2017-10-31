//
//  DockerImageInfo.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Freddy
import os

public struct DockerImageInfo: JSONDecodable, JSONEncodable {
	let size: Int
	let estSize: Int
	let tag: String
	let name: String
	let id: String
	var fullName: String { return tag }

	public init?(from: JSON?) {
		guard let json = from else { return nil }
		do {
			try self.init(json: json)
		} catch {
		}
		return nil
	}

	public init(json: JSON) throws {
		size = try json.getInt(at: "size")
		tag = try json.getString(at: "tag", or: "")
		name = try json.getString(at: "name")
		id = try json.getString(at: "id")
		estSize = try json.getInt(at: "estSize")
	}

	public func toJSON() -> JSON {
		return .dictionary(["size": .int(size), "tag": .string(tag), "name": .string(name), "id": .string(id)])
	}
}

extension DockerImageInfo: Equatable {
	public static func == (lhs: DockerImageInfo, rhs: DockerImageInfo) -> Bool {
		return lhs.id == rhs.id && lhs.tag == rhs.tag && lhs.size == rhs.size
	}
}

public struct RequiredImageInfo: Collection, JSONDecodable, JSONEncodable {
	static let supportedVersion = 2
	
	let version: Int
	let timestamp: Date
	let combined: DockerImageInfo

	static let timestampFormatter: ISO8601DateFormatter = {
		var df = ISO8601DateFormatter()
		df.formatOptions = [.withInternetDateTime]
		return df
	}()
	
	var timestampString: String { return RequiredImageInfo.timestampFormatter.string(from: timestamp) }
	
	public init?(from: JSON?) {
		guard let json = from else { return nil }
		do {
			try self.init(json: json)
		} catch {
			return nil
		}
	}

	public init(json: JSON) throws {
		version = try json.getInt(at: "version")
		guard version == RequiredImageInfo.supportedVersion else {
			throw DockerError.internalError("unsupported imageInfo version (\(version))")
		}
		guard let ts = type(of: self).timestampFormatter.date(from: try json.getString(at: "timestamp")) else {
			throw DockerError.invalidJson(nil) //FIXME: report nested error
		}
		timestamp = ts
		let imageDict = try json.decodedDictionary(at: "images", type: DockerImageInfo.self)
		guard let comp = imageDict["combined"] else {
			throw DockerError.invalidJson(nil) //FIXME: report nested error
		}
		combined = comp
	}

	/// Is this version newer than other
	///
	/// - Parameter other: another instance of RequiredImageInfo
	/// - Returns: true if this version is newer
	public func newerThan(_ other: RequiredImageInfo?) -> Bool {
		guard nil != other else { return true }
		return version == other!.version && timestamp > other!.timestamp
	}
	
	public var startIndex: Int { return 0 }
	public var endIndex: Int { return 3 }

	public subscript(index: Int) -> DockerImageInfo {
		return combined
//		switch index {
//			case 0: return combined
//			default: fatalError("index out of bounds")
//		}
	}

	public subscript(type: ContainerType) -> DockerImageInfo {
		return combined
	}

	public func index(after i: Int) -> Int {
		precondition(i < endIndex)
		return i + 1
	}

	public func toJSON() -> JSON {
		return .dictionary(["version": .int(version), "timestamp": .string(timestampString), "images": ["combined": combined].toJSON()])
	}
}
