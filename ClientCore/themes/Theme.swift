//
//  Theme.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Freddy
import os

public protocol ThemeProperty: RawRepresentable, Hashable {
	static var allValues: [Self] { get }
	var stringValue: String { get }
}

public protocol Theme: JSONEncodable, JSONDecodable, CustomStringConvertible {
	associatedtype Property: ThemeProperty
	/// the name for this type's property in an NSAttributedString
	static var AttributeName: String { get }
	/// implemented in protocol extension to allow using AttributeName w/o the type name
	var attributeName: String { get }
	
	/// name of the theme
	var name: String { get }
	/// number of properties
	var propertyCount: Int { get }
	/// true if the theme is system-defined and not editable
	var isBuiltin: Bool { get set }

	func color(for property: Property) -> PlatformColor
	
	static func loadThemes(from: URL, builtin: Bool) -> [Self]
}

public extension Theme {
	/// map the static AttributeName to a non-static property so type name is not required to reference it
	public var attributeName: String { return type(of: self).AttributeName }
	
	static func loadThemes(from url: URL, builtin: Bool = false) -> [Self] {
		if builtin {
			do {
				let data = try Data(contentsOf: url)
				let json = try JSON(data: data)
				return try json.decodedArray().sorted(by: { $0.name < $1.name })
			} catch {
				fatalError("failed to decode builtin themes \(error)")
			}
		}
		var themes = [Self]()
		var urls = [URL]()
		do {
			urls = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
		} catch {
			os_log("exception getting user themes")
			return themes
		}
		urls.forEach { aFile in
			guard aFile.pathExtension == "json" else { return }
			do {
				let data = try Data(contentsOf: aFile)
				let json = try JSON(data: data)
				var theme: Self = try json.decode()
				theme.isBuiltin = builtin
				themes.append(theme)
			} catch {
				os_log("error reading a theme")
			}
		}
		return themes
	}
}

/// type-erased wrapper around a theme
//public struct AnyTheme<Nested: Theme>: Theme {
//	public typealias Property = Nested.Property
//
//	private let _theme: Nested
//
//	public init(theme: Nested) {
//		_theme = theme
//	}
//
//	public var attributeName: String { return _theme.attributeName }
//	public var name: String { return _theme.name }
//	public var colors: [T.Property: PlatformColor] { return _theme.colors }
//	public var propertyCount: Int { return _theme.propertyCount }
//	public var isBuiltin: Bool { return _theme.isBuiltin }
//	public var description: String { return _theme.description }
//}
