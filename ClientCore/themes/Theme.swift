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
import os

/// enum for the different properties supported by a theme
public protocol ThemeProperty: RawRepresentable, Hashable {
	/// returns array of all properties
	static var allProperties: [Self] { get }
	/// returns array of all background properties
	static var backgroundProperties: [Self] { get }
	/// returns array of all text/foreground properties
	static var foregroundProperties: [Self] { get }
	/// returns the label to use for the property in a json file
	var stringValue: String { get }
}

public protocol Theme: NSObjectProtocol, JSONEncodable, JSONDecodable, CustomStringConvertible {
	associatedtype Property: ThemeProperty
	/// the name for this type's property in an NSAttributedString
	static var AttributeName: String { get }
	/// implemented in protocol extension to allow using AttributeName w/o the type name
	var attributeName: String { get }
	
	/// returns the default theme to use
	static var defaultTheme: Self { get }
	
	/// name of the theme
	var name: String { get }
	/// number of properties
	var propertyCount: Int { get }
	/// true if the theme is system-defined and not editable
	var isBuiltin: Bool { get set }

	func color(for property: Property) -> PlatformColor
	
	/// returns an array of themes loaded from the specified URL.
	static func loadThemes(from: URL, builtin: Bool) -> [Self]
	
	/// attributes to add to a NSAttributedString to represent the theme property
	func stringAttributes(for property: Property) -> [String: Any]

	/// Updates the attributed string so its attributes use this theme
	///
	/// - Parameter attributedString: The string whose attributes will be updated
	func update(attributedString: NSMutableAttributedString)
}

public extension Theme {
	/// map the static AttributeName to a non-static property so type name is not required to reference it
	public var attributeName: String { return type(of: self).AttributeName }
	
	static func loadThemes(from url: URL, builtin: Bool = false) -> [Self] {
		guard !builtin else { return loadBuiltinThemes(from: url) }
		var themes = [Self]()
		var urls = [URL]()
		do {
			urls = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
		} catch {
			os_log("error getting user themes")
			return themes
		}
		urls.forEach { aFile in
			guard aFile.pathExtension == "json" else { return }
			do {
				let data = try Data(contentsOf: aFile)
				let json = try JSON(data: data)
				let theme: Self = try json.decode()
				theme.isBuiltin = builtin
				themes.append(theme)
			} catch {
				os_log("error reading theme from %{public}s: %{public}s", log: .app, aFile.lastPathComponent, error.localizedDescription)
			}
		}
		return themes
	}

	static func loadBuiltinThemes(from url: URL) -> [Self] {
		do {
			let data = try Data(contentsOf: url)
			let json = try JSON(data: data)
			let themes = try json.decodedArray(type: Self.self).sorted(by: { $0.name < $1.name })
			themes.forEach { $0.isBuiltin = true }
			return themes
		} catch {
			fatalError("failed to decode builtin themes \(error)")
		}
	}
	
	/// attributes to add to a NSAttributedString to represent the theme property
	public func stringAttributes(for property: Property) -> [String: Any] {
		return [attributeName: property,
		        NSBackgroundColorAttributeName: color(for: property)]
			as [String: Any]
	}
	
	/// Updates the attributed string so its attributes use this theme
	///
	/// - Parameter attributedString: The string whose attributes will be updated
	public func update(attributedString: NSMutableAttributedString) {
		attributedString.enumerateAttribute(attributeName, in: attributedString.string.fullNSRange)
		{ (rawProperty, range, _) in
			guard let rawProperty = rawProperty,
				let property = rawProperty as? Property
				else { return } //should never fail
			attributedString.setAttributes(stringAttributes(for: property), range: range)
		}
	}
}
