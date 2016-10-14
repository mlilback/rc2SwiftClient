//
//  DockerImage.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import SwiftyJSON

public struct DockerImage: JSONSerializable, Named {
	let id: String
	let tags: [DockerTag]
	let size: Int
	var labels: [String:String] = [:]

	public init?(json: JSON?) {
		guard let json = json else { return nil }
		id = json["Id"].stringValue
		self.size = json["Size"].intValue
		var localTags: [DockerTag] = []
		for aTag in json["RepoTags"].arrayValue {
			if let tag = DockerTag(tag: aTag.stringValue) {
				localTags.append(tag)
			}
		}
		self.tags = localTags
		for (key, value) in json["Labels"].dictionaryValue {
			labels[key] = value.stringValue
		}
	}

	public func serialize() throws -> JSON {
		var dict: [String:AnyObject] = [:]
		dict["Id"] = id as AnyObject?
		dict["Size"] = size as AnyObject?
		var outTags: [JSON] = []
		for aTag in tags {
			outTags.append(try aTag.serialize())
		}
		return JSON(["Id": JSON(id), "Size": JSON(size), "RepoTags": JSON(outTags)])
	}

	public func isNamed(_ str: String) -> Bool {
		for (_, aTag) in tags.enumerated() {
			if aTag.description.hasPrefix(str) { return true }
		}
		return false
	}
}

extension DockerImage: Equatable {
	public static func == (lhs: DockerImage, rhs: DockerImage) -> Bool {
		return lhs.id == rhs.id && lhs.size == rhs.size
	}
}
