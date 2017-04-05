//
//  HelpController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import ClientCore
import Foundation
import os

class HelpController {
	static let shared = HelpController()
	fileprivate let db: FMDatabase
	
	let packages: [HelpTopic]
	let allTopics: Set<HelpTopic>
	let allTopicNames: Set<String>
	fileprivate let topicsByName: [String: [HelpTopic]]
	fileprivate var rootHelpUrl: URL
	fileprivate(set) var baseHelpUrl: URL
	
	///loads topics from storage
	init() {
		//make sure our help directory exists
		let fileManager = FileManager()
		let dbpath = Bundle(for: type(of: self)).path(forResource: "helpindex", ofType: "db")
		do {
			rootHelpUrl = try AppInfo.subdirectory(type: .applicationSupportDirectory, named: "rdocs")
			baseHelpUrl = rootHelpUrl.appendingPathComponent("helpdocs/library", isDirectory: true)
			if !rootHelpUrl.directoryExists() {
				try fileManager.createDirectory(at: rootHelpUrl, withIntermediateDirectories: true, attributes: nil)
			}
			//load help index
			db = FMDatabase(path: dbpath)
			db.open()
			var topsByPack = [String: [HelpTopic]]()
			var topsByName = [String: [HelpTopic]]()
			var all = Set<HelpTopic>()
			var names = Set<String>()
			let rs = try db.executeQuery("select rowid,package,name,title,aliases,desc from helptopic where name not like '.%' order by package, name COLLATE nocase ", values: nil)
			while rs.next() {
				guard let package = rs.string(forColumn: "package") else { continue }
				let topic = HelpTopic(id: Int(rs.int(forColumn: "rowid")), name: rs.string(forColumn: "name"), packageName: package, title: rs.string(forColumn: "title"), aliases: rs.string(forColumn: "aliases"), description: rs.string(forColumn: "desc"))
				if topsByPack[package] == nil {
					topsByPack[package] = []
				}
				topsByPack[package]!.append(topic)
				all.insert(topic)
				for anAlias in (topic.aliases! + [topic.name]) {
					names.insert(anAlias)
					if var atops = topsByName[anAlias] {
						atops.append(topic)
					} else {
						topsByName[anAlias] = [topic]
					}
				}
			}
			var packs: [HelpTopic] = []
			topsByPack.forEach { (key, ptopics) in
				let package = HelpTopic(name: key, subtopics: ptopics.sorted(by: { return $0.compare($1) }))
				packs.append(package)
			}
			self.packages = packs.sorted(by: { return $0.compare($1) })
			self.allTopics = all
			self.allTopicNames = names
			self.topicsByName = topsByName
		} catch let error as NSError {
			os_log("error loading help index: %{public}@", log: .app, type:.error, error)
			fatalError("failed to load help index")
		}
	}
	
	deinit {
		db.close()
	}
	
	/// checks to make sure help files exist and if not, extract them from tarball
	func verifyDocumentationInstallation() {
		let versionUrl = rootHelpUrl.appendingPathComponent("rc2help.json")
		if versionUrl.fileExists() { return }
		let tar = Process()
		tar.currentDirectoryPath = baseHelpUrl.path
		let tarball = Bundle(for: type(of: self)).url(forResource: "rdocs", withExtension: "tgz")
		precondition(tarball != nil && tarball!.fileExists())
		tar.arguments = ["zxf", tarball!.path]
		tar.launchPath = "/usr/bin/tar"
		tar.terminationHandler = { process in
			if process.terminationStatus != 0 {
				os_log("help extraction failed: %d", log: .app, type: .default, process.terminationReason.rawValue)
			}
		}
		tar.launch()
	}
	
	/// returns true if there is a help topic with the specified name
	func hasTopic(_ name: String) -> Bool {
		return allTopicNames.contains(name)
	}
	
	func topic(withId topicId: Int) -> HelpTopic? {
		return allTopics.first(where: { $0.topicId == topicId })
	}
	
	fileprivate func parseResultSet(_ rs: FMResultSet) throws -> [HelpTopic] {
		var topicsByPack = [String: [HelpTopic]]()
		while rs.next() {
			guard let package = rs.string(forColumn: "package") else { continue }
			let topic = HelpTopic(name: rs.string(forColumn: "name"), packageName:package, title: rs.string(forColumn: "title"), aliases:rs.string(forColumn: "aliases"), description: rs.string(forColumn: "desc"))
			if topicsByPack[package] == nil {
				topicsByPack[package] = []
			}
			topicsByPack[package]!.append(topic)
		}
		let matches: [HelpTopic] = topicsByPack.map { HelpTopic(name: $0, subtopics: $1) }
		return matches.sorted(by: { return $0.compare($1) })
	}
	
	/// returns a list of HelpTopics that contain the searchString in their title
	func searchTitles(_ searchString: String) -> [HelpTopic] {
		let results = allTopics.filter { $0.name.localizedCaseInsensitiveContains(searchString) }
		var topicsByPack = [String: [HelpTopic]]()
		for aMatch in results {
			if topicsByPack[aMatch.packageName] == nil {
				topicsByPack[aMatch.packageName] = []
			}
			topicsByPack[aMatch.packageName]!.append(aMatch)
		}
		let matches: [HelpTopic] = topicsByPack.map { HelpTopic(name: $0, subtopics: $1) }
		return matches.sorted(by: { return $0.compare($1) })
	}
	
	/// returns a list of HelpTpics that contain the searchString in their title or summary
	func searchTopics(_ searchString: String) -> [HelpTopic] {
		guard searchString.characters.count > 0 else { return packages }
		var results: [HelpTopic] = []
		do {
			let rs = try db.executeQuery("select * from helpidx where helpidx match ?", values: [searchString])
			results = try parseResultSet(rs)
		} catch let error as NSError {
			os_log("error searching help: %{public}@", log: .app, error)
		}
		return results
	}
	
	//can't share code with initializer because functions can't be called in init before all properties are assigned
	func topicsWithName(_ targetName: String) -> [HelpTopic] {
		var packs: [HelpTopic] = []
		var topsByPack = [String: [HelpTopic]]()
		topicsByName[targetName]?.forEach { aTopic in
			if var existPacks = topsByPack[aTopic.packageName] {
				existPacks.append(aTopic)
				topsByPack[aTopic.name] = existPacks
			} else {
				topsByPack[aTopic.packageName] = [aTopic]
			}
		}
		topsByPack.forEach { (key, ptopics) in
			let package = HelpTopic(name: key, subtopics: ptopics.sorted(by: { return $0.compare($1) }))
			packs.append(package)
		}
		packs = packs.reduce([], { (pks, ht) in
			var myPacks = pks
			if ht.subtopics != nil { myPacks.append(contentsOf: ht.subtopics!) }
			return myPacks
		})
		packs = packs.sorted(by: { return $0.compare($1) })
		return packs
	}

	func urlForTopic(_ topic: HelpTopic) -> URL {
		let str = "\(topic.packageName)\(HelpUrlFuncSeperator)/\(topic.name).html"
		let helpUrl = baseHelpUrl.appendingPathComponent(str)
		if !helpUrl.fileExists() {
			os_log("missing help file: %{public}s", log: .app, str)
		}
		return helpUrl
	}
}
