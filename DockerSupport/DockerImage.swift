//
//  DockerImage.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Freddy
import ClientCore

public struct DockerImage: JSONDecodable, Named {
	let id: String
	let tags: [DockerTag]
	let size: Int
	var labels: [String:String] = [:]

	/// JSONDecodable support. not implemented in an extension because is not a convience initializer
	public init(json: JSON) throws {
		id = try json.getString(at: "Id")
		self.size = try json.getInt(at: "Size")
		var localTags: [DockerTag] = []
		for aTag in try json.decodedArray(at: "RepoTags", type: String.self) {
			if let tag = DockerTag(tag: aTag), tag.name != "none" {
				localTags.append(tag)
			}
		}
		self.tags = localTags
		for (key, value) in try json.decodedDictionary(at: "Labels", type: String.self) {
			labels[key] = value
		}
	}

	public func isNamed(_ str: String) -> Bool {
		for aTag in tags {
			if aTag.description.hasPrefix(str) { return true }
		}
		return false
	}
}

extension DockerImage: JSONEncodable {
	public func toJSON() -> JSON {
		var dict: [String:AnyObject] = [:]
		dict["Id"] = id as AnyObject?
		dict["Size"] = size as AnyObject?
		let outTags = tags.map { $0.toJSON() }
		return .dictionary(["Id": .string(id), "Size": .int(size), "RepoTags": .array(outTags)])
	}
}

extension DockerImage: Equatable {
	public static func == (lhs: DockerImage, rhs: DockerImage) -> Bool {
		return lhs.id == rhs.id && lhs.size == rhs.size
	}
}
