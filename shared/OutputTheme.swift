  //
//  OutputTheme.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import Freddy
import ClientCore

protocol Theme {
	var name: String { get }
}

enum OutputThemeProperty: String {
	case background, text, note, help, error, log, input, status

	static var allValues: [OutputThemeProperty] { return [.background, .text, .note, .help, .error, .log, .input, .status] }
}

final class OutputTheme: NSObject, Theme, JSONDecodable {
	var name: String
	var colors = Dictionary<OutputThemeProperty, PlatformColor>()
	dynamic var isBuiltin: Bool = false
	
	init(name: String) {
		self.name = name
		super.init()
	}
	
	init(json: JSON) throws {
		name = try json.getString(at: "ThemeName")
		super.init()
		try OutputThemeProperty.allValues.forEach { property in
			colors[property] = PlatformColor(hexString: try json.getString(at: property.rawValue))
		}
	}
	
	func color(for property: OutputThemeProperty) -> PlatformColor {
		return colors[property]!
	}
	
	func value(for property: OutputThemeProperty) -> String {
		return colors[property]!.hexString
	}
}
