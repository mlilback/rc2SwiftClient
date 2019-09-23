//
//  SyntaxTheme.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import SwiftyUserDefaults

public enum SyntaxThemeProperty: String, ThemeProperty, CaseIterable {
	
	case background, text, codeBackground, inlineBackground, equationBackground, comment, quote, keyword, function, symbol
	
	public var stringValue: String { return rawValue }
	public static var allProperties: [SyntaxThemeProperty] { return [.background, codeBackground, .inlineBackground, .equationBackground, .text, .comment, .quote, .keyword, .function, .symbol] }
	public static var backgroundProperties: [SyntaxThemeProperty] { return [.background, .codeBackground, .inlineBackground, .equationBackground] }
	public static var foregroundProperties: [SyntaxThemeProperty] { return [.text, .comment, .quote, .keyword, .function, .symbol] }
}

public final class SyntaxTheme: BaseTheme, DefaultsSerializable {
	public static let AttributeName = NSAttributedString.Key("rc2.SyntaxTheme")
	
	private enum MyKeys: String, CodingKey {
		case name = "ThemeName"
		case background
		case text
		case codeBackground
		case inlineBackground
		case equationBackground
		case comment
		case quote
		case keyword
		case function
		case symbol
	}
	
	var colors = [SyntaxThemeProperty: PlatformColor]()
	
	public override var propertyCount: Int { return colors.count }
	
	public override var description: String { return "SyntaxTheme \(name)" }
	
	public required init(from decoder: Decoder) throws {
		try super.init(from: decoder)
		let container = try decoder.container(keyedBy: MyKeys.self)
		name = try container.decode(String.self, forKey: .name)
		colors[.background] = PlatformColor(hexString: try container.decode(String.self, forKey: .background))
		colors[.text] = PlatformColor(hexString: try container.decode(String.self, forKey: .text))
		colors[.codeBackground] = PlatformColor(hexString: try container.decode(String.self, forKey: .codeBackground))
		colors[.inlineBackground] = PlatformColor(hexString: try container.decode(String.self, forKey: .inlineBackground))
		colors[.equationBackground] = PlatformColor(hexString: try container.decode(String.self, forKey: .equationBackground))
		colors[.comment] = PlatformColor(hexString: try container.decode(String.self, forKey: .comment))
		colors[.quote] = PlatformColor(hexString: try container.decode(String.self, forKey: .quote))
		colors[.keyword] = PlatformColor(hexString: try container.decode(String.self, forKey: .keyword))
		colors[.function] = PlatformColor(hexString: try container.decode(String.self, forKey: .function))
		colors[.symbol] = PlatformColor(hexString: try container.decode(String.self, forKey: .symbol))

	}
	
	public override init(name: String) {
		super.init(name: name)
	}
	
	public override func encode(to encoder: Encoder) throws {
		//make sure hve all colors
		for aProp in SyntaxThemeProperty.allCases {
			guard colors[aProp] != nil else { fatalError("theme \(name) is missing value for \(aProp.rawValue)") }
		}
		var container = encoder.container(keyedBy: MyKeys.self)
		try container.encode(name, forKey: .name)
		try container.encode(colors[.background]?.hexString, forKey: .background)
		try container.encode(colors[.text]?.hexString, forKey: .text)
		try container.encode(colors[.codeBackground]?.hexString, forKey: .codeBackground)
		try container.encode(colors[.inlineBackground]?.hexString, forKey: .inlineBackground)
		try container.encode(colors[.equationBackground]?.hexString, forKey: .equationBackground)
		try container.encode(colors[.comment]?.hexString, forKey: .comment)
		try container.encode(colors[.quote]?.hexString, forKey: .quote)
		try container.encode(colors[.keyword]?.hexString, forKey: .keyword)
		try container.encode(colors[.function]?.hexString, forKey: .function)
		try container.encode(colors[.symbol]?.hexString, forKey: .symbol)
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
	
//	public override func stringAttributes<T: ThemeProperty>(for property: T) -> [NSAttributedStringKey: Any] {
//		guard let prop = property as? SyntaxThemeProperty else { fatalError("unsupported property") }
//		return [attributeName: property, NSAttributedStringKey.backgroundColor: color(for: prop)]
//	}

	public func stringAttributes(for property: SyntaxThemeProperty) -> [NSAttributedString.Key: Any] {
		return [attributeName: property, NSAttributedString.Key.backgroundColor: color(for: property)]
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
		// system was giving values from greyspace, not rgb. force rgb.
		let white = PlatformColor.init(hexString: "FFFFFF")
		let black = PlatformColor.init(hexString: "000000")
		theme.colors[.text] = black
		for prop in SyntaxThemeProperty.backgroundProperties {
			theme.colors[prop] = white
		}
		for prop in SyntaxThemeProperty.foregroundProperties {
			theme.colors[prop] = black
		}
		return theme
	}()
}
