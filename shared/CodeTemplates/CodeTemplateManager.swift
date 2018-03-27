//
//  CodeTemplateManager.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import GRDB

public enum TemplateType: Int {
	case markdown, rCode, equation
}

extension TemplateType: DatabaseValueConvertible { }

public struct TemplateCategory: RowConvertible {
	public init(row: Row) {
		self.id = row["id"]
		self.name = row["name"]
	}
	
	public let id: Int
	public let name: String
}

public class CodeTemplateManager {
	private let dataUrl: URL
	private let dbQueue: DatabaseQueue
	public private(set) var categories: [TemplateCategory] = []
	
	public init(dataFileUrl: URL) throws {
		if !dataFileUrl.fileExists() {
			guard let defaultFileUrl = Bundle.main.url(forResource: "codetemplates", withExtension: "db") else {
				fatalError("default template file not found")
			}
			try FileManager.default.copyItem(at: defaultFileUrl, to: dataFileUrl)
		}
		dataUrl = dataFileUrl
		dbQueue = try DatabaseQueue(path: dataUrl.path)
		try dbQueue.inDatabase { db in
			try db.execute("pragma foreign_keys = ON;")
			categories = try TemplateCategory.fetchAll(db, "select * from TemplateCategory")
		}
	}
}
