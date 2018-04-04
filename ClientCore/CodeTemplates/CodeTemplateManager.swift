//
//  CodeTemplateManager.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Rc2Common
import MJLLogger

public enum TemplateType: String {
	case markdown, rCode, equation
	static var allCases: [TemplateType] { return [.markdown, .rCode, .equation] }
}

/// manages loading/saving of code templates
public class CodeTemplateManager {
	
	private let dataFolderUrl: URL
	private var categories: [TemplateType: [CodeTemplateCategory]]

	public init(dataFolderUrl: URL, defaultFolderUrl: URL, fileManager: FileManager = .default) throws {
		self.dataFolderUrl = dataFolderUrl
		self.categories = [:]
		if !fileManager.directoryExists(at: dataFolderUrl) {
			do {
				try fileManager.createDirectory(at: dataFolderUrl, withIntermediateDirectories: true, attributes: nil)
			} catch {
				fatalError("failed to create code template directory")
			}
		}
		for aType in TemplateType.allCases {
			let templates = categories(type: aType, defaultFolderUrl: defaultFolderUrl)
			categories[aType] = templates
		}
	}
	
	/// save data for all types
	public func saveAll() throws {
		try TemplateType.allCases.forEach { try self.save(type: $0) }
	}
	
	/// save data for the particular type
	public func save(type: TemplateType) throws {
		guard let cats = categories[type] else { fatalError("no category \(type)")}
		let encoder = JSONEncoder()
		let destUrl = dataFolderUrl.appendingPathComponent("\(type.rawValue).json")
		do {
			let data = try encoder.encode(cats)
			try data.write(to: destUrl)
		} catch {
			Log.warn("failed to save CodeTemplates: \(error)", .core)
			throw error
		}
	}
	
	/// return the categories for a particular type
	public func templates(for type: TemplateType) -> [CodeTemplateCategory] {
		return categories[type] ?? []
	}
	
	/// reads the stored values of the specified type from the dataFolderUrl. If there is no file there, it loads one from defaultFolderUrl. If there isn't one there, it loads a hardcoded general category.
	private func categories(type: TemplateType, defaultFolderUrl: URL) -> [CodeTemplateCategory] {
		let decoder = JSONDecoder()
		// start with a dummy value
		var templates: [CodeTemplateCategory] = [CodeTemplateCategory(name: "General")]
		let filename = "\(type.rawValue).json"
		var fileUrl = dataFolderUrl.appendingPathComponent(filename)
		if !fileUrl.fileExists() {
			fileUrl = defaultFolderUrl.appendingPathComponent(filename)
			if !fileUrl.fileExists() { return templates }
		}
		do {
			let data = try Data(contentsOf: fileUrl)
			templates = try decoder.decode([CodeTemplateCategory].self, from: data)
		} catch {
			Log.error("failed to read \(fileUrl.path)", .core)
		}
		return templates
	}
}
