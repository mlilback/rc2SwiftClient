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
	public static var allProperties: [SyntaxThemeProperty] { return [.background, codeBackground, .inlineBackground, .equationBackground, .text, .comment, .quote, .keyword, .function, .symbol] }
	public static var backgroundProperties: [SyntaxThemeProperty] { return [.background, .codeBackground, .inlineBackground, .equationBackground] }
	public static var foregroundProperties: [SyntaxThemeProperty] { return [.text, .comment, .quote, .keyword, .function, .symbol] }
}

public final class SyntaxTheme: BaseTheme {
	public static let AttributeName = NSAttributedStringKey("rc2.SyntaxTheme")
	
	var colors = [SyntaxThemeProperty: PlatformColor]()
	
	public override var propertyCount: Int { return colors.count }
	
	public override var description: String { return "SyntaxTheme \(name)" }
	
	public required init(json: JSON) throws {
		try super.init(json: json)
		try SyntaxThemeProperty.allProperties.forEach { property in
			colors[property] = PlatformColor(hexString: try json.getString(at: property.rawValue))
		}
	}
	
	public override init(name: String) {
		super.init(name: name)
	}
	
	public func color(for property: SyntaxThemeProperty) -> PlatformColor {
		return colors[property] ?? PlatformColor.black
	}
	
	/// support for accessing colors via subscripting
	public subscript(key: SyntaxThemeProperty) -> PlatformColor? {
		get {
			return colors[key]
		}
		set (newValue) {
			guard !isBuiltin else { fatalError("builtin themes are not editable") }
			guard let newValue = newValue else { fatalError("theme colors cannot be nil") }
			colors[key] = newValue
		}
	}
	
	public override func toJSON() -> JSON {
		var props = [String: JSON]()
		props["ThemeName"] = .string(name)
		for (key, value) in colors {
			props[key.rawValue] = .string(value.hexString)
		}
		return .dictionary(props)
	}
	
//	public override func stringAttributes<T: ThemeProperty>(for property: T) -> [NSAttributedStringKey: Any] {
//		guard let prop = property as? SyntaxThemeProperty else { fatalError("unsupported property") }
//		return [attributeName: property, NSAttributedStringKey.backgroundColor: color(for: prop)]
//	}

	public func stringAttributes(for property: SyntaxThemeProperty) -> [NSAttributedStringKey: Any] {
		return [attributeName: property, NSAttributedStringKey.backgroundColor: color(for: property)]
	}

	public override func update(attributedString: NSMutableAttributedString) {
		attributedString.enumerateAttribute(attributeName, in: attributedString.string.fullNSRange)
		{ (rawProperty, range, _) in
			guard let rawProperty = rawProperty,
				let property = rawProperty as? SyntaxThemeProperty
				else { return } //should never fail
			attributedString.setAttributes(stringAttributes(for: property), range: range)
		}
	}

	func duplicate(name: String) -> SyntaxTheme {
		let other = SyntaxTheme(name: name)
		other.colors = colors
		other.dirty = true
		return other
	}
	
	public static let defaultTheme: Theme = {
		var theme = SyntaxTheme(name: "builtin")
		theme.colors[.text] = PlatformColor.black
		for prop in SyntaxThemeProperty.backgroundProperties {
			theme.colors[prop] = PlatformColor.white
		}
		return theme
	}()
}
