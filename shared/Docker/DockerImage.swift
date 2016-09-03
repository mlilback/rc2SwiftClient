//
//  DockerImage.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import SwiftyJSON

public struct DockerTag: CustomStringConvertible {
	let repo:String?
	let name:String
	let version:String?
	let isLatest:Bool = false
	
	///tag formatted as [repo/]name[:version]
	public var description: String {
		return "\(repo == nil ? "" : repo! + "/")\(name)\(version == nil ? "" : ":version!")"
	}

	///parses a tag string to create the instance. Only works with tags of the format [repo/][tag][:version]
	public init?(tag:String) {
		let reg = try! NSRegularExpression(pattern: "(([\\w][\\w.-]+)/)?([\\w][\\w.-]+)(:([\\w][\\w.-]+))?", options: [])
		guard let match = reg.firstMatchInString(tag, options: [], range: tag.toNSRange) else { return nil }
		switch match.numberOfRanges {
			case 6:
				self.init(repo: match.stringAtIndex(2, forString: tag), name: match.stringAtIndex(3, forString: tag)!, version: match.stringAtIndex(5, forString: tag))
			case 4:
				self.init(repo: nil, name: match.stringAtIndex(1, forString: tag)!, version: match.stringAtIndex(3, forString: tag))
			case 2:
				self.init(repo: nil, name: match.stringAtIndex(1, forString: tag)!, version: nil)
			default:
				return nil
		}
	}
	
	public init(repo:String?, name:String, version:String?) {
		self.repo = repo
		self.name = name
		self.version = version
	}
}

public struct DockerImage: JSONSerializable {
	let id:String
	let tags:[DockerTag]
	let size:Int
	
	public init?(json:JSON) {
		id = json["Id"].stringValue
		self.size = json["Size"].intValue
		var localTags:[DockerTag] = []
		for aTag in json["RepoTags"].arrayValue {
			if let tag = DockerTag(tag: aTag.stringValue) {
				localTags.append(tag)
			}
		}
		self.tags = localTags
	}
	
	public func serialize() throws -> JSON {
		var dict:[String:AnyObject] = [:]
		dict["Id"] = id
		dict["Size"] = size
		var outTags:[String] = []
		for aTag in tags {
			outTags.append(aTag.description)
		}
		dict["RepoTags"] = outTags
		return JSON(dict)
	}
	
}
