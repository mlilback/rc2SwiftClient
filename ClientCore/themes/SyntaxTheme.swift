//
//  SyntaxTheme.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Freddy

public enum SyntaxThemeProperty: String, ThemeProperty {
	
	case background, text, codeBackground, inlineBackground, equationBackground, comment, quote, keyword, function, symbol
	
	public var stringValue: String { return rawValue }
	public static var allProperties: [SyntaxThemeProperty] { return [.background, .text, .codeBackground, .inlineBackground, .equationBackground, .comment, .quote, .keyword, .function, .symbol] }
	public static var backgroundProperties: [SyntaxThemeProperty] { return [.background, .codeBackground, .inlineBackground, .equationBackground] }
	public static var foregroundProperties: [SyntaxThemeProperty] { return [.text, .comment, .quote, .keyword, .function, .symbol] }
}

public final class SyntaxTheme: NSObject, Theme, JSONDecodable, JSONEncodable {
	public static let AttributeName = "rc2.SyntaxTheme"
	
	public var name: String
	public var colors = [SyntaxThemeProperty: PlatformColor]()
	public var isBuiltin: Bool = false
	
	public var propertyCount: Int { return colors.count }
	
	override public var description: String { return "SyntaxTheme \(name)" }
	
	init(name: String) {
		self.name = name
		super.init()
	}
	
	public init(json: JSON) throws {
		name = try json.getString(at: "ThemeName")
		super.init()
		try SyntaxThemeProperty.allProperties.forEach { property in
			colors[property] = PlatformColor(hexString: try json.getString(at: property.rawValue))
		}
	}
	
	public func color(for property: SyntaxThemeProperty) -> PlatformColor {
		return colors[property] ?? PlatformColor.black
	}
	
	public func toJSON() -> JSON {
		var props = [String: JSON]()
		props["ThemeName"] = .string(name)
		for (key, value) in colors {
			props[key.rawValue] = .string(value.hexString)
		}
		return .dictionary(props)
	}
	
	public static let defaultTheme: SyntaxTheme = {
		var theme = SyntaxTheme(name: "builtin")
		theme.colors[.text] = PlatformColor.black
		for prop in SyntaxThemeProperty.backgroundProperties {
			theme.colors[prop] = PlatformColor.white
		}
		return theme
	}()
}
