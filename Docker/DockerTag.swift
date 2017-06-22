//
//  DockerType.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Freddy

///Representation of a tag on a docker image
public struct DockerTag: JSONDecodable, CustomStringConvertible, Hashable {
	let repo: String?
	let name: String
	let version: String?
	let isLatest: Bool = false

	///tag formatted as [repo/]name[:version]
	public var description: String {
		return "\(repo == nil ? "" : repo! + "/")\(name)\(version == nil ? "" : ":\(version!)")"
	}

	///parses a tag string to create the instance. Only works with tags of the format [repo/][tag][:version]
	public init?(tag: String) {
		// swiftlint:disable:next force_try
		let reg = try! NSRegularExpression(pattern: "(([\\w][\\w.-]+)/)?([\\w][\\w.-]+)(:([\\w]?[\\w.-]+))?", options: [])
		guard let match = reg.firstMatch(in: tag, options: [], range: tag.fullNSRange) else { return nil }
		var repo: String?
		var name: String
		var version: String?
		if match.range(at:5).length > 0 {
			version = match.string(index: 5, forString: tag)
		}
		if match.range(at:2).length > 0 {
			repo = match.string(index:2, forString:tag)
		}
		name = match.string(index: 3, forString: tag)!
		self.init(repo:repo, name:name, version:version)
	}

	public init(repo: String?, name: String, version: String?) {
		self.repo = repo
		self.name = name
		self.version = version
	}

	public init?(from: JSON?) {
		guard let json = from else { return nil }
		do {
			try self.init(json: json)
		} catch {
		}
		return nil
	}

	public init(json: JSON) throws {
		self.repo = try json.getString(at: "repo")
		self.name = try json.getString(at: "name")
		self.version = try json.getString(at: "version")
	}

	public var hashValue: Int { return description.hashValue }

}

extension DockerTag: JSONEncodable {
	public func toJSON() -> JSON {
		var dict = [String: String]()
		if let aRep = repo { dict["repo"] = aRep }
		dict["name"] = name
		if let aVer = version { dict["version"] = aVer }
		return dict.toJSON()
	}
}

public func == (lhs: DockerTag, rhs: DockerTag) -> Bool {
	return lhs.repo == rhs.repo && lhs.name == rhs.name && lhs.version == rhs.version
}
