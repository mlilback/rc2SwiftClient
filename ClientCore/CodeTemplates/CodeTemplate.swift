//
//  CodeTemplate.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import ReactiveSwift

public protocol CodeTemplateObject: class {
	var name: MutableProperty<String> { get }
}

/// a user-defined category to organize CodeTemplates in
public class CodeTemplateCategory: Codable, CodeTemplateObject {
	private enum CodingKeys: String, CodingKey {
		case name
		case templates
	}
	
	/// the name of the category
	public var name: MutableProperty<String>
	/// the templates contained in the category
	public var templates: MutableProperty<[CodeTemplate]>
	
	public init(name: String) {
		self.name = MutableProperty<String>(name)
		self.templates = MutableProperty<[CodeTemplate]>([])
	}
	
	public required init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		let dname = try container.decode(String.self, forKey: .name)
		name = MutableProperty<String>(dname)
		templates = MutableProperty<[CodeTemplate]>(try container.decode([CodeTemplate].self, forKey: .templates))
	}
	
	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(name.value, forKey: .name)
		try container.encode(templates.value, forKey: .templates)
	}
}

/// represents a named template for code
public class CodeTemplate: Codable, CodeTemplateObject {
	private enum CodingKeys: String, CodingKey {
		case name
		case contents
	}
	
	///  the name of the template
	public var name: MutableProperty<String>
	/// the contents of the template
	public var contents: MutableProperty<String>
	
	public init(name: String, contents: String) {
		self.name = MutableProperty<String>(name)
		self.contents = MutableProperty<String>(contents)
	}
	
	public required init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		let dname = try container.decode(String.self, forKey: .name)
		let dcontents = try container.decode(String.self, forKey: .contents)
		self.name = MutableProperty<String>(dname)
		self.contents = MutableProperty<String>(dcontents)
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(name.value, forKey: .name)
		try container.encode(contents.value, forKey: .contents)
	}
}
