//
//  HelpTopic.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

/// Represents a help page or a package of pages
class HelpTopic: Hashable {
	/// a unique id per topic. nil if isPackage is true
	let topicId: Int?
	/// name of the topic
	let name: String
	/// true if this topic represents a package that groups other topics
	let isPackage: Bool
	/// the title to display
	let title: String?
	/// the short description of the topic
	let desc: String?
	/// known aliases for the topic
	let aliases: [String]?
	/// if isPackage is true, the topics contained in this package
	let subtopics: [HelpTopic]?
	/// if isPackage is true, the package name. Otherwise, the same as title
	let packageName: String

	///initializer for a package description
	init(name: String, subtopics: [HelpTopic]) {
		self.isPackage = true
		self.topicId = nil
		self.name = name
		self.packageName = name
		self.title = nil
		self.desc = nil
		self.aliases = nil
		self.subtopics = subtopics
	}

	///initializer for an actual topic
	init(id: Int? = nil, name: String, packageName: String, title: String, aliases: String, description: String?) {
		self.isPackage = false
		self.topicId = id
		self.name = name
		self.packageName = packageName
		self.title = title
		self.desc = description
		self.subtopics = nil
		self.aliases = aliases.components(separatedBy: ":")
	}

	var hashValue: Int { return ObjectIdentifier(self).hashValue }

	static func == (lhs: HelpTopic, rhs: HelpTopic) -> Bool {
		return ObjectIdentifier(lhs).hashValue == ObjectIdentifier(rhs).hashValue
	}

	///convience for sorting
	func compare(_ other: HelpTopic) -> Bool {
		return self.name.caseInsensitiveCompare(other.name) == .orderedAscending
	}

	///accesor function to be passed around as a closure
	static func subtopicsAccessor(_ topic: HelpTopic) -> [HelpTopic]? {
		return topic.subtopics
	}
}
