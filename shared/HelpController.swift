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
	let subtopics:[HelpTopic]?
	
	///initializer for a package description
	init(name:String, subtopics:[HelpTopic]) {
		self.isPackage = true
		self.name = name
		self.title = nil
		self.desc = nil
		self.subtopics = subtopics
	}
	
	///initializer for an actual topic
	init(name:String, title:String, description:String?) {
		self.isPackage = false
		self.name = name
		self.title = title
		self.desc = description
		self.subtopics = nil
		super.init()
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
	
	let packages:[HelpTopic]
	let allTopics:Set<HelpTopic>
	
	///loads topics from storage
	init() {
		let dbpath = NSBundle.mainBundle().pathForResource("helpindex", ofType: "db")
		do {
			let db = FMDatabase(path: dbpath)
			db.open()
			var topsByPack = [String:[HelpTopic]]()
			var all = Set<HelpTopic>()
			let rs = try db.executeQuery("select package,name,title,desc from helptopic where name not like '.%' order by package, name COLLATE nocase ", values: nil)
			while rs.next() {
				let package = rs.stringForColumn("package")
				let topic = HelpTopic(name: rs.stringForColumn("name"), title: rs.stringForColumn("title"), description: rs.stringForColumn("desc"))
				if topsByPack[package] == nil {
					topsByPack[package] = []
				}
				topsByPack[package]!.append(topic)
				all.insert(topic)
			}
			db.close()
			var packs:[HelpTopic] = []
			topsByPack.forEach() { (key, ptopics) in
				packs.append(HelpTopic(name: key, subtopics: ptopics.sort({ return $0.compare($1) })))
			}
			self.packages = packs.sort({ return $0.compare($1) })
			self.allTopics = all
		} catch let error as NSError {
			log.error("error loading help index: \(error)")
			fatalError("failed to load help index")
		}
	}
	
	func topicsStartingWith(namePrefix:String) -> [HelpTopic] {
		return allTopics.flatMap({ (aTopic) -> HelpTopic? in
			if aTopic.name.hasPrefix(namePrefix) { 	return aTopic }
			return nil
		})
	}
}
