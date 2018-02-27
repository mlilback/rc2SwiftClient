//
//  Theme.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

#if os(OSX)
	import AppKit
#else
	import UIKit
#endif
import Foundation
import Freddy
import MJLLogger

public protocol ThemeProperty {
	var stringValue: String { get }
	var localizedDescription: String { get }
}

/// enum for the different properties supported by a theme
//public protocol ThemeProperty: RawRepresentable, Hashable {
//	/// returns array of all properties
//	static var allProperties: [Self] { get }
//	/// returns array of all background properties
//	static var backgroundProperties: [Self] { get }
//	/// returns array of all text/foreground properties
//	static var foregroundProperties: [Self] { get }
//	/// returns the label to use for the property in a json file
//	var stringValue: String { get }
//	/// returns a localized version of this property's name. Looked up as TypeName.stringValue by protocol extension
//	var localizedDescription: String { get }
//}

extension ThemeProperty {
	public var localizedDescription: String {
		let key = "\(String(describing: type(of: self))).\(stringValue)"
		return NSLocalizedString(key, value: stringValue, comment: "")
	}
}

public protocol Theme: JSONEncodable, JSONDecodable, CustomStringConvertible {
	
	/// the name for this type's property in an NSAttributedString
//	static var AttributeName: NSAttributedStringKey { get }
	/// implemented in protocol extension to allow using AttributeName w/o the type name
	var attributeName: NSAttributedStringKey { get }
	/// for user-editable themes, the file location of this theme
	var fileUrl: URL? { get }
	
	/// returns the default theme to use
//	static var defaultTheme: Theme { get }
	
	/// name of the theme
	var name: String { get }
	/// number of properties
	var propertyCount: Int { get }
	/// true if the theme is system-defined and not editable
	var isBuiltin: Bool { get }

//	func color(for property: SyntaxThemeProperty) -> PlatformColor
//	subscript(key: SyntaxThemeProperty) -> PlatformColor? { get set }

	/// returns an array of themes loaded from the specified URL.
//	static func loadThemes(from: URL, builtin: Bool) -> [Self]
	
	/// attributes to add to a NSAttributedString to represent the theme property
//	func stringAttributes(for property: SyntaxThemeProperty) -> [NSAttributedStringKey: Any]

	/// Updates the attributed string so its attributes use this theme
	///
	/// - Parameter attributedString: The string whose attributes will be updated
	func update(attributedString: NSMutableAttributedString)
}

public class BaseTheme: NSObject, Theme {
//	public static var defaultTheme: Theme = { fatalError("subclass must implement") }()
	
	public func toJSON() -> JSON {
		fatalError("subclass must implement and write ThemeName")
	}
	
	public init(name: String) {
		self.name = name
	}
	
	public required init(json: JSON) throws {
		name = try json.getString(at: "ThemeName")
	}
	
	public override var description: String { return "Theme \(name)" }
	
	/// map the static AttributeName to a non-static property so type name is not required to reference it
	public let attributeName: NSAttributedStringKey = NSAttributedStringKey("rc2.BaseTheme")
	
	public var allProperties: [ThemeProperty] {
		if type(of: self) == SyntaxTheme.self { return SyntaxThemeProperty.allProperties }
		return OutputThemeProperty.allProperties
	}
	
	public internal(set) var name: String
	public internal(set) var isBuiltin: Bool = false
	public internal(set) var fileUrl: URL?
	var dirty: Bool = false

	public var propertyCount: Int { return 0 }
	
	public func color(for property: ThemeProperty) -> PlatformColor {
		if let syntax = self as? SyntaxTheme, let prop = property as? SyntaxThemeProperty {
			return syntax.color(for: prop)
		} else if let output = self as? OutputTheme, let prop = property as? OutputThemeProperty {
			return output.color(for: prop)
		}
		Log.warn("unknown theme property \(property.localizedDescription)", .core)
		return NSColor.black
	}
	
	static public func loadThemes<T: BaseTheme>(from url: URL, builtin: Bool = false) -> [T] {
		guard !builtin else { return loadBuiltinThemes(from: url) }
		var themes = [T]()
		var urls = [URL]()
		do {
			urls = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
		} catch {
			Log.warn("error getting user themes: \(error)", .core)
			return themes
		}
		urls.forEach { aFile in
			guard aFile.pathExtension == "json" else { return }
			do {
				let data = try Data(contentsOf: aFile)
				let json = try JSON(data: data)
				let theme: T = try json.decode()
				theme.isBuiltin = builtin
				theme.fileUrl = aFile
				themes.append(theme)
			} catch {
				Log.warn("error reading theme from \(aFile.lastPathComponent): \(error)", .app)
			}
		}
		return themes
	}

	static func loadBuiltinThemes<T: BaseTheme>(from url: URL) -> [T] {
		do {
			let data = try Data(contentsOf: url)
			let json = try JSON(data: data)
			let themes: [T] = try json.decodedArray().sorted(by: { $0.name < $1.name })
			themes.forEach { $0.isBuiltin = true }
			return themes
		} catch {
			fatalError("failed to decode builtin themes \(error)")
		}
	}
	
	/// attributes to add to a NSAttributedString to represent the theme property
//	public func stringAttributes<T: ThemeProperty>(for property: T) -> [NSAttributedStringKey: Any] {
//		return [:]
//	}
	
	/// Updates the attributed string so its attributes use this theme
	///
	/// - Parameter attributedString: The string whose attributes will be updated
	public func update(attributedString: NSMutableAttributedString) {
		fatalError("subclass must implement")
//		attributedString.enumerateAttribute(attributeName, in: attributedString.string.fullNSRange)
//		{ (rawProperty, range, _) in
//			guard let rawProperty = rawProperty,
//				let property = rawProperty as? ThemeProperty
//				else { return } //should never fail
//			attributedString.setAttributes(stringAttributes(for: property), range: range)
//		}
	}
}
