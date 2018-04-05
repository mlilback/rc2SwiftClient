//
//  CodeTemplate.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

public protocol CodeTemplateObject: class {
	var name: String { get set }
}

/// a user-defined category to organize CodeTemplates in
public class CodeTemplateCategory: Codable, CodeTemplateObject {
	/// the name of the category
	public var name: String
	/// the templates contained in the category
	public var templates: [CodeTemplate]
	
	public init(name: String) {
		self.name = name
		self.templates = []
	}
}

/// represents a named template for code
public class CodeTemplate: Codable, CodeTemplateObject {
	///  the name of the template
	public var name: String
	/// the contents of the template
	public var contents: String
	
	public init(name: String, contents: String) {
		self.name = name
		self.contents = contents
	}
}
