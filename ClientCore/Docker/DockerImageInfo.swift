//
//  DockerImageInfo.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import SwiftyJSON
import os

public struct DockerImageInfo: JSONSerializable {
	let size:Int64
	let dupSize:Int64
	let name:String
	let id:String

	public init(json:JSON) {
		size = json["size"].int64Value
		dupSize = json["dupsize"].int64Value
		name = json["name"].stringValue
		id = json["id"].stringValue
	}

	public func serialize() throws -> JSON {
		var dict = [String:Any]()
		dict["size"] = size
		dict["dupsize"] = dupSize
		dict["name"] = name
		dict["id"] = id
		return JSON(dict)
	}
}

public struct RequiredImageInfo: JSONSerializable {
	let version: Int
	let dbserver: DockerImageInfo
	let appserver: DockerImageInfo
	let computeserver: DockerImageInfo
	
	public init(json:JSON) {
		version = json["version"].intValue
		dbserver = DockerImageInfo(json: json["images"].dictionary!["dbserver"]!)
		appserver = DockerImageInfo(json: json["images"].dictionary!["appserver"]!)
		computeserver = DockerImageInfo(json: json["images"].dictionary!["compute"]!)
	}

	public func serialize() throws -> JSON {
		do {
			let images = ["dbserver": try dbserver.serialize(), "appserver": try appserver.serialize(), "compute": try computeserver.serialize()]
			var dict:[String:JSON] = [:]
			dict["images"] = JSON(arrayLiteral: images)
			dict["version"] = JSON(version)
			return JSON(jsonDictionary: dict)
		} catch let err as NSError {
			os_log("error serializing: %{public}s", err)
			throw err
		}
	}
}
