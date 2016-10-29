//
//  DockerImageInfo.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import SwiftyJSON
import os

public struct DockerImageInfo: JSONSerializable {
	let size: Int64
	let tag: String
	let name: String
	let id: String
	var fullName: String { return "rc2server/\(name)" }

	public init?(json: JSON?) {
		guard let json = json else { return nil }
		size = json["size"].int64Value
		tag = json["tag"].stringValue
		name = json["name"].stringValue
		id = json["id"].stringValue
	}

	public func serialize() throws -> JSON {
		var dict = [String:Any]()
		dict["size"] = size
		dict["tag"] = tag
		dict["name"] = name
		dict["id"] = id
		return JSON(dict)
	}
}

public struct RequiredImageInfo: Collection, JSONSerializable {
	let version: Int
	let dbserver: DockerImageInfo
	let appserver: DockerImageInfo
	let computeserver: DockerImageInfo

	public init?(json: JSON?) {
		guard let json = json else { return nil }
		version = json["version"].intValue
		dbserver = DockerImageInfo(json: json["images"].dictionary!["dbserver"]!)!
		appserver = DockerImageInfo(json: json["images"].dictionary!["appserver"]!)!
		computeserver = DockerImageInfo(json: json["images"].dictionary!["compute"]!)!
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

	public func index(after i: Int) -> Int {
		precondition(i < endIndex)
		return i + 1
	}

	public func serialize() throws -> JSON {
		do {
			let images = ["dbserver": try dbserver.serialize(), "appserver": try appserver.serialize(), "compute": try computeserver.serialize()]
			var dict: [String:JSON] = [:]
			dict["images"] = JSON(arrayLiteral: images)
			dict["version"] = JSON(version)
			return JSON(jsonDictionary: dict)
		} catch let err as NSError {
			os_log("error serializing: %{public}s", err)
			throw err
		}
	}
}
