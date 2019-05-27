//
//  main.swift
//  HelpIndexTool
//
//  Created by Mark Lilback on 3/29/18.
//  Copyright © 2018 Rc2. All rights reserved.
//

import Foundation
import GRDB


func createIndex() {
	guard CommandLine.argc == 3 else { fatalError("invalid arguments") }
	let srcPath = CommandLine.arguments[1]
	let destPath = CommandLine.arguments[2]
	let fm = FileManager()
	guard fm.fileExists(atPath: srcPath), fm.fileExists(atPath: destPath) else { fatalError("arguments are not files") }
	do {
		let files = findJsonFiles(srcPath: srcPath, destPath: destPath)
		let dbQueue = try DatabaseQueue(path: "\(destPath)/helpindex.db")
		try dbQueue.inDatabase { db in
			try db.execute(sql: "drop table if exists helpidx")
			try db.execute(sql: "drop table if exists helptopic")
			try db.execute(sql: "create virtual table helpidx using fts4(package,name,title,aliases,desc, tokenize=porter)")
			try db.execute(sql: "create table helptopic (package, name, title, aliases, desc)")
		}
		for file in files {
			addJson(filePath: file, dbQueue: dbQueue)
		}
	} catch {
		fatalError("error: \(error)")
	}
}

struct HelpWrapper: Decodable {
	let help: [RawHelpTopic]
}

struct RawHelpTopic: Decodable {
	let desc: String
	let aliases: String
	let name: String
	let title: String
	let package: String
}

func addJson(filePath: String, dbQueue: DatabaseQueue) {
	guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else { fatalError("failed to read \(filePath)") }
	do {
		let validChars = NSMutableCharacterSet.alphanumeric()
		validChars.addCharacters(in: ".")
		let invalidChars = validChars.inverted
		let decoder = JSONDecoder()
		let wrapper = try decoder.decode(HelpWrapper.self, from: data)
		let topics = wrapper.help
		try dbQueue.inTransaction { db in
			let idxSql = "insert into helpidx values (?, ?, ?, ?, ?)"
			let topicSql = "insert into helptopic values (?, ?, ?, ?, ?)"
			let idxStatement = try db.makeUpdateStatement(sql: idxSql)
			let topicStatement = try db.makeUpdateStatement(sql: topicSql)
			for topic in topics {
				// remove any aliases with invalid characters
				let aliases = topic.aliases.components(separatedBy: ":").compactMap { if $0.rangeOfCharacter(from: invalidChars) != nil { return nil }
					return $0
				}.joined(separator: ":")
				let args: StatementArguments = [topic.package, topic.name, topic.title, aliases, topic.desc]
				try idxStatement.execute(arguments: args)
				try topicStatement.execute(arguments: args)
			}
			return .commit
		}
	} catch {
		fatalError("error parsing \(filePath): \(error)")
	}
}

func findJsonFiles(srcPath: String, destPath: String) -> [String] {
	let fm = FileManager()
	do {
		let paths = try fm .contentsOfDirectory(atPath: srcPath)
		return paths.compactMap { path in
			if path.hasSuffix(".json") {
				return srcPath + "/" + path
			}
			return nil
		}
	} catch {
		fatalError("error reading json files: \(error)")
	}
}

createIndex()

