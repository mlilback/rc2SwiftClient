//
//  CodeTemplateManager.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Rc2Common
import MJLLogger
import Parsing
//import SyntaxParsing
import SwiftyUserDefaults

public extension Notification.Name {
	static let codeTemplatesChanged = Notification.Name("CodeTempaltesChanged")
}

public enum TemplateType: String, Codable, DefaultsSerializable {
	case markdown, rCode, equation
	public static var allCases: [TemplateType] { return [.markdown, .rCode, .equation] }
	
	public static var _defaults: DefaultsBridge<TemplateType> { return DefaultsRawRepresentableBridge() }
	public static var _defaultsArray: DefaultsBridge<[TemplateType]> { return DefaultsRawRepresentableArrayBridge() }

	/// localized title to use for displaying to user
	public var title: String {
		switch self {
		case .rCode: return NSLocalizedString("RCodeChunkMenuTitle", value: "R Code", comment: "")
		case .markdown: return NSLocalizedString("MarkdownChunkMenuTitle", value: "Markdown", comment: "")
		case .equation: return NSLocalizedString("EquationChunkMenuTitle", value: "Equation", comment: "")
		}
	}
	
	/// create from a ChunkType from the syntax parser
	public init(chunkType: RootChunkType) {
		switch chunkType {
		case .code: self = .rCode
		case .markdown: self = .markdown
		case .equation: self = .equation
		}
	}
	
	/// return the SyntaxParser ChunkType equivelent of this TemplateType
	public var chunkType: ChunkType {
		switch self {
		case .markdown: return .markdown
		case .rCode: return .code
		case .equation: return .equation
		}
	}
}

/// manages loading/saving of code templates
public class CodeTemplateManager {
	
	private let dataFolderUrl: URL
	private let notificationCenter: NotificationCenter
	private var categories: [TemplateType: [CodeTemplateCategory]]
	/// flag to prevent multiple changed notifications being sent in a row
	private var saveAllInProgress = false

	public init(dataFolderUrl: URL, defaultFolderUrl: URL, notificationCenter: NotificationCenter = .default, fileManager: FileManager = .default) throws {
		self.dataFolderUrl = dataFolderUrl
		self.notificationCenter = notificationCenter
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
		saveAllInProgress = true
		try TemplateType.allCases.forEach { try self.save(type: $0) }
		saveAllInProgress = false
		notificationCenter.post(name: .codeTemplatesChanged, object: self)
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
		if !saveAllInProgress {
			notificationCenter.post(name: .codeTemplatesChanged, object: self)
		}
	}
	
	/// return the categories for a particular type
	public func categories(for type: TemplateType) -> [CodeTemplateCategory] {
		return categories[type] ?? []
	}
	
	public func set(categories newCats: [CodeTemplateCategory], for type: TemplateType) {
		categories[type] = newCats
	}
	
	/// creates a new CodeTemplateCategory and inserts it the array of categories for type at the desired index
	public func createCategory(of type: TemplateType, at destIndex: Int) -> CodeTemplateCategory {
		let cat = CodeTemplateCategory(name: "Untitled")
		categories[type]!.insert(cat, at: destIndex)
		return cat
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
