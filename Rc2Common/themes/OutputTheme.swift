//
//  OutputTheme.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import SwiftyUserDefaults

public enum OutputThemeProperty: String, ThemeProperty, CaseIterable {

	case background, text, note, help, error, log, input, status

	public var stringValue: String { return rawValue }
	public static var allProperties: [OutputThemeProperty] { return [.background, .text, .note, .help, .error, .log, .input, .status] }
	public static var backgroundProperties: [OutputThemeProperty] { return [.background] }
	public static var foregroundProperties: [OutputThemeProperty] { return [.text, .note, .help, .error, .log, .input, .status] }
}

public final class OutputTheme: BaseTheme, DefaultsSerializable {
	public static let AttributeName = NSAttributedString.Key("rc2.OutputTheme")

	var colors = [OutputThemeProperty: PlatformColor]()

	public override var propertyCount: Int { return colors.count }
	public override var description: String { return "OutputTheme \(name)" }

	private enum MyKeys: String, CodingKey {
		case name = "ThemeName"
		case background
		case text
		case note
		case help
		case error
		case log
		case input
		case status
	}
	
	override init(name: String) {
		super.init(name: name)
	}

	public required init(from decoder: Decoder) throws {
		try super.init(from: decoder)
		let container = try decoder.container(keyedBy: MyKeys.self)
		name = try container.decode(String.self, forKey: .name)
		colors[.background] = PlatformColor(hexString: try container.decode(String.self, forKey: .background))
		colors[.text] = PlatformColor(hexString: try container.decode(String.self, forKey: .text))
		colors[.note] = PlatformColor(hexString: try container.decode(String.self, forKey: .note))
		colors[.help] = PlatformColor(hexString: try container.decode(String.self, forKey: .help))
		colors[.error] = PlatformColor(hexString: try container.decode(String.self, forKey: .error))
		colors[.log] = PlatformColor(hexString: try container.decode(String.self, forKey: .log))
		colors[.input] = PlatformColor(hexString: try container.decode(String.self, forKey: .input))
		colors[.status] = PlatformColor(hexString: try container.decode(String.self, forKey: .status))
	}

	override public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: MyKeys.self)
		try container.encode(name, forKey: .name)
		try container.encode(colors[.background]?.hexString, forKey: .background)
		try container.encode(colors[.text]?.hexString, forKey: .text)
		try container.encode(colors[.note]?.hexString, forKey: .note)
		try container.encode(colors[.help]?.hexString, forKey: .help)
		try container.encode(colors[.error]?.hexString, forKey: .error)
		try container.encode(colors[.log]?.hexString, forKey: .log)
		try container.encode(colors[.input]?.hexString, forKey: .input)
		try container.encode(colors[.status]?.hexString, forKey: .status)
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
//	public override func stringAttributes<T: ThemeProperty>(for property: T) -> [NSAttributedStringKey: Any] {
//		guard let prop = property as? OutputThemeProperty else { fatalError("unsupported property") }
//		return [attributeName: property, NSAttributedStringKey.backgroundColor: color(for: prop)]
//	}

	public func stringAttributes(for property: OutputThemeProperty) -> [NSAttributedString.Key: Any] {
		return [attributeName: property, NSAttributedString.Key.backgroundColor: color(for: property)]
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
