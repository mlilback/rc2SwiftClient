//
//  OutputTheme.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import Freddy
import ClientCore

public protocol Theme {
	var name: String { get }
}

public enum OutputThemeProperty: String {

	case background, text, note, help, error, log, input, status

	public static var allValues: [OutputThemeProperty] { return [.background, .text, .note, .help, .error, .log, .input, .status] }
}

extension Notification.Name {
	public static let outputThemeChanged = Notification.Name("rc2.activeOutputThemeChanged")
}

public final class OutputTheme: NSObject, Theme, JSONDecodable, JSONEncodable {
	public static let AttributeName = "rc2.OutputTheme"
	public let attributeName = OutputTheme.AttributeName
	
	public var name: String
	var colors = Dictionary<OutputThemeProperty, PlatformColor>()
	public dynamic var isBuiltin: Bool = false
	
	public var propertyCount: Int { return colors.count }
	
	override public var description: String { return "OutputTheme \(name)" }
	
	init(name: String) {
		self.name = name
		super.init()
	}
	
	public init(json: JSON) throws {
		name = try json.getString(at: "ThemeName")
		super.init()
		try OutputThemeProperty.allValues.forEach { property in
			colors[property] = PlatformColor(hexString: try json.getString(at: property.rawValue))
		}
	}
	
	public func color(for property: OutputThemeProperty) -> PlatformColor {
		return colors[property] ?? PlatformColor.white
	}
	
	public func value(for property: OutputThemeProperty) -> String {
		if let color = colors[property] { return color.hexString }
		return "ffffff" //default to white
	}
	
	public func toJSON() -> JSON {
		var props = [String: JSON]()
		props["ThemeName"] = .string(name)
		for (key, value) in colors {
			props[key.rawValue] = .string(value.hexString)
		}
		return .dictionary(props)
	}
	
	/// attributes to add to a NSAttributedString to represent the theme property
	public func stringAttributes(for property: OutputThemeProperty) -> [String: Any] {
		return [attributeName: property,
		        NSBackgroundColorAttributeName: color(for: property)]
			as [String: Any]
	}
	
	/// Updates the attributed string so its attributes use this theme
	///
	/// - Parameter attributedString: The string whose attributes will be updated
	public func update(attributedString: NSMutableAttributedString) {
		attributedString.enumerateAttribute(attributeName, in: attributedString.string.fullNSRange)
		{ (rawProperty, range, stop) in
			guard let rawProperty = rawProperty,
				let property = rawProperty as? OutputThemeProperty
				else { return } //should never fail
			attributedString.setAttributes(stringAttributes(for: property), range: range)
		}
	}
	
	public static let defaultTheme: OutputTheme = {
		var theme = OutputTheme(name: "builtin")
		theme.colors[.text] = PlatformColor.black
		return theme
	}()
}
