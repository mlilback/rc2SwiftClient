//
//  DockerType.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import SwiftyJSON
import ClientCore

///Representation of a tag on a docker image
public struct DockerTag: JSONSerializable, CustomStringConvertible, Hashable {
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
		guard let match = reg.firstMatch(in: tag, options: [], range: tag.toNSRange) else { return nil }
		switch match.numberOfRanges {
		case 6:
			self.init(repo: match.string(index:2, forString: tag), name: match.string(index:3, forString: tag)!, version: match.string(index:5, forString: tag))
		case 4:
			self.init(repo: nil, name: match.string(index:1, forString: tag)!, version: match.string(index:3, forString: tag))
		case 2:
			self.init(repo: nil, name: match.string(index:1, forString: tag)!, version: nil)
		default:
			return nil
		}
	}
	
	public init(repo:String?, name:String, version:String?) {
		self.repo = repo
		self.name = name
		self.version = version
	}

	public init?(json:JSON) {
		self.repo = json["repo"].string
		self.name = json["name"].stringValue
		self.version = json["version"].string
	}
	
	public func serialize() throws -> JSON {
		var dict = Dictionary<String,String>()
		if let aRep = repo { dict["repo"] = aRep }
		dict["name"] = name
		if let aVer = version { dict["version"] = aVer }
		return JSON(dict)
	}

	public var hashValue: Int { return description.hashValue }
	
}

public func ==(lhs:DockerTag, rhs:DockerTag) -> Bool {
	return lhs.repo == rhs.repo && lhs.name == rhs.name && lhs.version == rhs.version
}
