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

public final class OutputTheme: BaseTheme {
	public static let AttributeName = NSAttributedStringKey("rc2.OutputTheme")

	var colors = [OutputThemeProperty: PlatformColor]()

	public override var propertyCount: Int { return colors.count }
	public override var description: String { return "OutputTheme \(name)" }

	override init(name: String) {
		super.init(name: name)
	}

	public required init(json: JSON) throws {
		try super.init(json: json)
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

	public override func toJSON() -> JSON {
		var props = [String: JSON]()
		props["ThemeName"] = .string(name)
		for (key, value) in colors {
			props[key.rawValue] = .string(value.hexString)
		}
		return .dictionary(props)
	}

//	public override func stringAttributes<T: ThemeProperty>(for property: T) -> [NSAttributedStringKey: Any] {
//		guard let prop = property as? OutputThemeProperty else { fatalError("unsupported property") }
//		return [attributeName: property, NSAttributedStringKey.backgroundColor: color(for: prop)]
//	}

	public func stringAttributes(for property: OutputThemeProperty) -> [NSAttributedStringKey: Any] {
		return [attributeName: property, NSAttributedStringKey.backgroundColor: color(for: property)]
	}

	public override func update(attributedString: NSMutableAttributedString) {
		attributedString.enumerateAttribute(attributeName, in: attributedString.string.fullNSRange)
		{ (rawProperty, range, _) in
			guard let rawProperty = rawProperty,
				let property = rawProperty as? OutputThemeProperty
				else { return } //should never fail
			attributedString.setAttributes(stringAttributes(for: property), range: range)
		}
	}

	func duplicate(name: String) -> OutputTheme {
		let other = OutputTheme(name: name)
		other.colors = colors
		other.dirty = true
		return other
	}

	public static let defaultTheme: Theme = {
		var theme = OutputTheme(name: "builtin")
		theme.colors[.text] = PlatformColor.black
		theme.colors[.background] = PlatformColor.white
		return theme
	}()
}
