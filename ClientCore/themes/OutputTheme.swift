//
//  OutputTheme.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import Freddy

public enum OutputThemeProperty: String, ThemeProperty {

	case background, text, note, help, error, log, input, status

	public var stringValue: String { return rawValue }
	public static var allProperties: [OutputThemeProperty] { return [.background, .text, .note, .help, .error, .log, .input, .status] }
	public static var backgroundProperties: [OutputThemeProperty] { return [.background] }
	public static var foregroundProperties: [OutputThemeProperty] { return [.text, .note, .help, .error, .log, .input, .status] }
}

public final class OutputTheme: NSObject, InternalTheme, JSONDecodable, JSONEncodable {
	public static let AttributeName = "rc2.OutputTheme"
	
	public var name: String
	var colors = [OutputThemeProperty: PlatformColor]()
	public var isBuiltin: Bool = false
	public var fileUrl: URL?
	var dirty: Bool = false
	
	public var propertyCount: Int { return colors.count }
	override public var description: String { return "OutputTheme \(name)" }
	
	init(name: String) {
		self.name = name
		super.init()
	}
	
	public init(json: JSON) throws {
		name = try json.getString(at: "ThemeName")
		super.init()
		try OutputThemeProperty.allProperties.forEach { property in
			colors[property] = PlatformColor(hexString: try json.getString(at: property.rawValue))
		}
	}
	
	public func color(for property: OutputThemeProperty) -> PlatformColor {
		return colors[property] ?? PlatformColor.black
	}
	
	/// support for accessing colors via subscripting
	public subscript(key: OutputThemeProperty) -> PlatformColor? {
		get {
			return colors[key]
		}
		set (newValue) {
			guard !isBuiltin else { fatalError("builtin themes are not editable") }
			guard let newValue = newValue else { fatalError("theme colors cannot be nil") }
			colors[key] = newValue
		}
	}
	
	public func toJSON() -> JSON {
		var props = [String: JSON]()
		props["ThemeName"] = .string(name)
		for (key, value) in colors {
			props[key.rawValue] = .string(value.hexString)
		}
		return .dictionary(props)
	}
	
	public static let defaultTheme: OutputTheme = {
		var theme = OutputTheme(name: "builtin")
		theme.colors[.text] = PlatformColor.black
		theme.colors[.background] = PlatformColor.white
		return theme
	}()
}
