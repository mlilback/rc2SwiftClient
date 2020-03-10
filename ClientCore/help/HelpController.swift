//
//  HelpController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Rc2Common
import Foundation
import MJLLogger
import GRDB
import ZIPFoundation
import ReactiveSwift

private let currentHelpVersion = 4

public class HelpController {
	let helpUrlFuncSeperator = "/html"
	
	static public let shared = HelpController()
	private let dbQueue: DatabaseQueue

	public let packages: [HelpTopic]
	public let allTopics: Set<HelpTopic>
	public let allTopicNames: Set<String>
	fileprivate let topicsByName: [String: [HelpTopic]]
	fileprivate var rootHelpUrl: URL
	public private(set) var baseHelpUrl: URL
	private let verified = Atomic<Bool>(false)

	///loads topics from storage
	public init() {
		guard let dbpath = Bundle(for: type(of: self)).path(forResource: "helpindex", ofType: "db")
			else { fatalError("helpindex resource missing") }
		do {
			//load help index
			dbQueue = try DatabaseQueue(path: dbpath)
			var topsByPack = [String: [HelpTopic]]()
			var topsByName = [String: [HelpTopic]]()
			var all = Set<HelpTopic>()
			var names = Set<String>()
			try dbQueue.inDatabase { db in
				let rawRows = try Row.fetchAll(db, sql: "select rowid,package,name,title,aliases,desc from helptopic where name not like '.%' order by package, name COLLATE nocase ")
				for row in rawRows {
					guard let package: String = row["package"] else { continue }
					let topic = HelpTopic(id: row["rowid"], name: row["name"], packageName: package, title: row["title"], aliases: row["aliases"], description: row["desc"])
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
			}
			var packs: [HelpTopic] = []
			topsByPack.forEach { (pair) in
				let package = HelpTopic(name: pair.key, subtopics: pair.value.sorted(by: { return $0.compare($1) }))
				packs.append(package)
			}
			self.packages = packs.sorted(by: { return $0.compare($1) })
			self.allTopics = all
			self.allTopicNames = names
			self.topicsByName = topsByName

			// ensure help files are installed
			rootHelpUrl = try AppInfo.subdirectory(type: .applicationSupportDirectory, named: "rdocs")
			baseHelpUrl = rootHelpUrl.appendingPathComponent("helpdocs/library", isDirectory: true)
			verifyDocumentationInstallation()
		} catch {
			Log.error("error loading help index: \(error)", .app)
			fatalError("failed to load help index")
		}
	}
	
	/// checks to make sure help files exist and if not, extract them from tarball
	public func verifyDocumentationInstallation() {
		if verified.value { return }
		defer { verified.value = true }
		let versionUrl = rootHelpUrl.appendingPathComponent("rc2help.json")
		// check to see if correct version installed
		if versionUrl.fileExists(),
			let vdata = try? Data(contentsOf: versionUrl),
			let vinfo = try? JSONDecoder().decode(HelpInfo.self, from: vdata),
			vinfo.version >= currentHelpVersion
		{ return }
		// need to install
		do {
			let fm = FileManager()
			if versionUrl.fileExists() {
				// zip won't onverwrite, so nuke existing
				try fm.removeItem(at: rootHelpUrl)
				try fm.createDirectory(at: rootHelpUrl, withIntermediateDirectories: true, attributes: nil)
			}
			let archive = Bundle(for: type(of: self)).url(forResource: "help", withExtension: "zip")!
			DispatchQueue.global().async { [rootHelpUrl] in
				do {
					try fm.unzipItem(at: archive, to: rootHelpUrl)
					Log.info("help extracted", .app)
				} catch {
					fatalError("error unzipping help: \(error)")
				}
			}
		} catch {
			fatalError("failed to read help.zip from app bundle")
		}
	}
	
	/// returns true if there is a help topic with the specified name
	public func hasTopic(_ name: String) -> Bool {
		return allTopicNames.contains(name)
	}
	
	public func topic(withId topicId: Int) -> HelpTopic? {
		return allTopics.first(where: { $0.topicId == topicId })
	}
	
	fileprivate func parse(rows: [Row]) throws -> [HelpTopic] {
		var topicsByPack = [String: [HelpTopic]]()
		for row in rows {
			guard let package: String = row["package"] else { continue }
			let topic = HelpTopic(name: row["name"], packageName: package, title: row["title"], aliases: row["aliases"], description: row["desc"])
			if topicsByPack[package] == nil {
				topicsByPack[package] = []
			}
			topicsByPack[package]!.append(topic)
		}
		let matches: [HelpTopic] = topicsByPack.map { pair in return HelpTopic(name: pair.key, subtopics: pair.value) }
		return matches.sorted(by: { return $0.compare($1) })
	}
	
	/// returns a list of HelpTopics that contain the searchString in their title
	public func searchTitles(_ searchString: String) -> [HelpTopic] {
		let results = allTopics.filter { $0.name.localizedCaseInsensitiveContains(searchString) }
		var topicsByPack = [String: [HelpTopic]]()
		for aMatch in results {
			if topicsByPack[aMatch.packageName] == nil {
				topicsByPack[aMatch.packageName] = []
			}
			topicsByPack[aMatch.packageName]!.append(aMatch)
		}
		let matches: [HelpTopic] = topicsByPack.map { pair in return HelpTopic(name: pair.key, subtopics: pair.value) }
		return matches.sorted(by: { return $0.compare($1) })
	}
	
	/// returns a list of HelpTpics that contain the searchString in their title or summary
	public func searchTopics(_ searchString: String) -> [HelpTopic] {
		guard searchString.count > 0 else { return packages }
		var results: [HelpTopic] = []
		var rows: [Row] = []
		do {
			try dbQueue.inDatabase { db in
				rows = try Row.fetchAll(db, sql: "select * from helpidx where helpidx match ?", arguments: [searchString])
			}
			results = try parse(rows: rows)
		} catch {
			Log.warn("error searching help: \(error)", .app)
		}
		return results
	}
	
	//can't share code with initializer because functions can't be called in init before all properties are assigned
	public func topicsWithName(_ targetName: String) -> [HelpTopic] {
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
		topsByPack.forEach { (arg) in
			let package = HelpTopic(name: arg.key, subtopics: arg.value.sorted(by: { return $0.compare($1) }))
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

	public func urlForTopic(_ topic: HelpTopic) -> URL {
		let str = "\(topic.packageName)\(helpUrlFuncSeperator)/\(topic.name).html"
		let helpUrl = baseHelpUrl.appendingPathComponent(str)
		if !helpUrl.fileExists() {
			Log.info("missing help file: \(str)", .app)
		}
		return helpUrl
	}
	
	private struct HelpInfo: Codable {
		let version: Int
	}
}
