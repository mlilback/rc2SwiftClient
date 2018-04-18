//
//  CodeTemplate.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import ReactiveSwift

public protocol CodeTemplateObject: NSObjectProtocol, Codable, CustomStringConvertible {
	var name: MutableProperty<String> { get }
}

/// a user-defined category to organize CodeTemplates in
public class CodeTemplateCategory: NSObject, Codable, CodeTemplateObject {
	private enum CodingKeys: String, CodingKey {
		case name
		case templates
	}
	
	public override var description: String { return "category \(name.value)" }
	
	/// the name of the category
	public var name: MutableProperty<String>
	/// the templates contained in the category
	public var templates: MutableProperty<[CodeTemplate]>
	
	public init(name: String) {
		self.name = MutableProperty<String>(name)
		self.templates = MutableProperty<[CodeTemplate]>([])
		super.init()
	}
	
	public init(_ other: CodeTemplateCategory) {
		self.name = MutableProperty(other.name.value)
		let otherTemplates = other.templates.value.map { CodeTemplate($0) }
		self.templates = MutableProperty(otherTemplates)
		super.init()
	}
	
	public required init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		let dname = try container.decode(String.self, forKey: .name)
		name = MutableProperty<String>(dname)
		templates = MutableProperty<[CodeTemplate]>(try container.decode([CodeTemplate].self, forKey: .templates))
		super.init()
	}
	
	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(name.value, forKey: .name)
		try container.encode(templates.value, forKey: .templates)
	}
}

/// represents a named template for code
public class CodeTemplate: NSObject, Codable, CodeTemplateObject {
	public static let selectionTemplateKey = "<!#selection#!>"

	private enum CodingKeys: String, CodingKey {
		case name
		case contents
		case type
	}
	
	public override var description: String { return "template \(name.value)" }
	
	///  the name of the template
	public var name: MutableProperty<String>
	/// the contents of the template
	public var contents: MutableProperty<String>
	/// the type of the template
	public let type: TemplateType
	
	public init(name: String, contents: String, type: TemplateType) {
		self.name = MutableProperty<String>(name)
		self.contents = MutableProperty<String>(contents)
		self.type = type
		super.init()
	}
	
	public required init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		let dname = try container.decode(String.self, forKey: .name)
		let dcontents = try container.decode(String.self, forKey: .contents)
		// if no type, assign to markdown
		let dtype = try TemplateType(rawValue: container.decode(String.self, forKey: .type)) ?? .markdown
		self.name = MutableProperty<String>(dname)
		self.contents = MutableProperty<String>(dcontents)
		self.type = dtype
		super.init()
	}

	public init(_ other: CodeTemplate) {
		self.name = MutableProperty(other.name.value)
		self.contents = MutableProperty(other.contents.value)
		self.type = other.type
		super.init()
	}

	public func contentsWith(selectionString: String) -> String {
		return contents.value.replacingOccurrences(of: CodeTemplate.selectionTemplateKey, with: selectionString)
	}
	
	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(name.value, forKey: .name)
		try container.encode(contents.value, forKey: .contents)
		try container.encode(type.rawValue, forKey: .type)
	}

	/// compares with another CodeTemplate. == operator tests if same instance in memory
	public func equals(_ object: CodeTemplate) -> Bool {
		return name.value == object.name.value && type == object.type && contents.value == object.contents.value
	}
}
