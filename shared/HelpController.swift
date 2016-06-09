//
//  HelpController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

class HelpTopic: NSObject {
	let name:String
	let isPackage:Bool
	let title:String?
	let desc:String?
	let aliases:[String]?
	let subtopics:[HelpTopic]?
	let packageName:String
	
	///initializer for a package description
	init(name:String, subtopics:[HelpTopic]) {
		self.isPackage = true
		self.name = name
		self.packageName = name
		self.title = nil
		self.desc = nil
		self.aliases = nil
		self.subtopics = subtopics
	}
	
	///initializer for an actual topic
	init(name:String, packageName:String, title:String, aliases:String, description:String?) {
		self.isPackage = false
		self.name = name
		self.packageName = packageName
		self.title = title
		self.desc = description
		self.subtopics = nil
		self.aliases = aliases.componentsSeparatedByString(":")
	}
	
	///convience for sorting
	func compare(other: HelpTopic) -> Bool {
		return self.name.caseInsensitiveCompare(other.name) == .OrderedAscending
	}
	
	///accesor function to be passed around as a closure
	static func subtopicsAccessor(topic:HelpTopic) -> [HelpTopic]? {
		return topic.subtopics
	}
}

class HelpController {
	static let sharedInstance = HelpController()
	private let db:FMDatabase
	
	let packages:[HelpTopic]
	let allTopics:Set<HelpTopic>
	let allTopicNames:Set<String>
	private let topicsByName:Dictionary<String, [HelpTopic]>
	
	///loads topics from storage
	init() {
		let dbpath = NSBundle.mainBundle().pathForResource("helpindex", ofType: "db")
		do {
			db = FMDatabase(path: dbpath)
			db.open()
			var topsByPack = [String:[HelpTopic]]()
			var topsByName = [String:[HelpTopic]]()
			var all = Set<HelpTopic>()
			var names = Set<String>()
			let rs = try db.executeQuery("select package,name,title,aliases,desc from helptopic where name not like '.%' order by package, name COLLATE nocase ", values: nil)
			while rs.next() {
				let package = rs.stringForColumn("package")
				let topic = HelpTopic(name: rs.stringForColumn("name"), packageName:package, title: rs.stringForColumn("title"), aliases:rs.stringForColumn("aliases"), description: rs.stringForColumn("desc"))
				if topsByPack[package] == nil {
					topsByPack[package] = []
				}
				topsByPack[package]!.append(topic)
				all.insert(topic)
				for anAlias in (topic.aliases! + [topic.name]) {
					names.insert(anAlias);
					if var atops = topsByName[anAlias] {
						atops.append(topic)
					} else {
						topsByName[anAlias] = [topic]
					}
				}
			}
			var packs:[HelpTopic] = []
			topsByPack.forEach() { (key, ptopics) in
				let package = HelpTopic(name: key, subtopics: ptopics.sort({ return $0.compare($1) }))
				packs.append(package)
			}
			self.packages = packs.sort({ return $0.compare($1) })
			self.allTopics = all
			self.allTopicNames = names
			self.topicsByName = topsByName
		} catch let error as NSError {
			log.error("error loading help index: \(error)")
			fatalError("failed to load help index")
		}
	}
	
	deinit {
		db.close()
	}
	
	func hasTopic(name:String) -> Bool {
		return allTopicNames.contains(name)
	}
	
	private func parseResultSet(rs:FMResultSet) throws -> [HelpTopic] {
		var topicsByPack = [String:[HelpTopic]]()
		while rs.next() {
			let package = rs.stringForColumn("package")
			let topic = HelpTopic(name: rs.stringForColumn("name"), packageName:package, title: rs.stringForColumn("title"), aliases:rs.stringForColumn("aliases"), description: rs.stringForColumn("desc"))
			if topicsByPack[package] == nil {
				topicsByPack[package] = []
			}
			topicsByPack[package]!.append(topic)
		}
		let matches:[HelpTopic] = topicsByPack.map() { HelpTopic(name: $0, subtopics: $1) }
		return matches.sort({ return $0.compare($1) })
	}
	
	func searchTopics(searchString:String) -> [HelpTopic] {
		guard searchString.characters.count > 0 else { return packages }
		var results:[HelpTopic] = []
		do {
			let rs = try db.executeQuery("select * from helpidx where helpidx match ?", values: [searchString])
			results = try parseResultSet(rs)
		} catch let error as NSError {
			log.warning("error searching help:\(error)")
		}
		return results
	}
	
	//can't share code with initializer because functions can't be called in init before all properties are assigned
	func topicsWithName(targetName:String) -> [HelpTopic] {
		var packs:[HelpTopic] = []
		var topsByPack = [String:[HelpTopic]]()
		topicsByName[targetName]?.forEach() { aTopic in
			if var existPacks = topsByPack[aTopic.packageName] {
				existPacks.append(aTopic)
				topsByPack[aTopic.name] = existPacks
			} else {
				topsByPack[aTopic.packageName] = [aTopic]
			}
		}
		topsByPack.forEach() { (key, ptopics) in
			let package = HelpTopic(name: key, subtopics: ptopics.sort({ return $0.compare($1) }))
			packs.append(package)
		}
		packs = packs.reduce([], combine: { (pks, ht) in
			var myPacks = pks
			if ht.subtopics != nil { myPacks.appendContentsOf(ht.subtopics!) }
			return myPacks
		})
		packs = packs.sort({ return $0.compare($1) })
		return packs
	}
	
	func topicsStartingWith(namePrefix:String) -> [HelpTopic] {
		var tops:[HelpTopic] = []
		topicsByName.forEach() { (tname, tarray) in
			if tname.hasPrefix(namePrefix) { tops += tarray }
		}
		return tops
	}
	
	func urlForTopic(topic:HelpTopic) -> NSURL {
		let str = "\(HelpUrlBase)/\(topic.packageName)\(HelpUrlFuncSeperator)/\(topic.name).html"
		return NSURL(string: str)!
	}
}
