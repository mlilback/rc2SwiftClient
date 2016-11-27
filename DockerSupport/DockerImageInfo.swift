//
//  DockerImageInfo.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Freddy
import os

public struct DockerImageInfo: JSONDecodable, JSONEncodable {
	let size: Int64
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
		size = Int64(try json.getInt(at: "size"))
		tag = try json.getString(at: "tag", or:"")
		name = try json.getString(at:"name")
		id = try json.getString(at: "id")
	}

	public func toJSON() -> JSON {
		return .dictionary(["size": .int(Int(size)), "tag": .string(tag), "name": .string(name), "id": .string(id)])
	}
}

public struct RequiredImageInfo: Collection, JSONDecodable, JSONEncodable {
	let version: Int
	let dbserver: DockerImageInfo
	let appserver: DockerImageInfo
	let computeserver: DockerImageInfo

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
		let imageDict = try json.decodedDictionary(at: "images", type: DockerImageInfo.self)
		guard let db = imageDict["dbserver"], let app = imageDict["appserver"], let comp = imageDict["compute"] else {
			throw DockerError.invalidJson
		}
		dbserver = db
		appserver = app
		computeserver = comp
	}

	public var startIndex: Int { return 0 }
	public var endIndex: Int { return 3 }

	public subscript(index: Int) -> DockerImageInfo {
		switch index {
			case 0: return dbserver
			case 1: return appserver
			case 2: return computeserver
			default: fatalError("index out of bounds")
		}
	}

	public subscript(type: ContainerType) -> DockerImageInfo {
		switch type {
			case .dbserver: return dbserver
			case .appserver: return appserver
			case .compute: return computeserver
		}
	}

	public func index(after i: Int) -> Int {
		precondition(i < endIndex)
		return i + 1
	}

	public func toJSON() -> JSON {
		return .dictionary(["version": .int(version), "images": ["dbserver": dbserver, "appserver": appserver, "compute": computeserver].toJSON()])
	}
}
