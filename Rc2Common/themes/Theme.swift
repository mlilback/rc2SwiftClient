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
import MJLLogger

enum ThemeType: String {
	case syntax
	case output
}

public protocol ThemeProperty {
	var stringValue: String { get }
	var localizedDescription: String { get }
}

extension ThemeProperty {
	public var localizedDescription: String {
		let key = "\(String(describing: type(of: self))).\(stringValue)"
		return NSLocalizedString(key, value: stringValue, comment: "")
	}
}

extension Notification.Name {
	/// posted when a SyntaxTheme has been modified. The object is the theme
	static let SyntaxThemeModified = Notification.Name(rawValue: "SyntaxThemeModified")
	/// posted when an OutputTheme has been modified. The object is the theme
	static let OutputThemeModified = Notification.Name(rawValue: "OutputThemeModified")
}

public protocol Theme: Codable, CustomStringConvertible {
	
	/// implemented in protocol extension to allow using AttributeName w/o the type name
	var attributeName: NSAttributedString.Key { get }
	/// for user-editable themes, the file location of this theme
	var fileUrl: URL? { get }
	
	/// name of the theme
	var name: String { get set }
	/// number of properties
	var propertyCount: Int { get }
	/// true if the theme is system-defined and not editable
	var isBuiltin: Bool { get }

	/// Updates the attributed string so its attributes use this theme
	///
	/// - Parameter attributedString: The string whose attributes will be updated
	func update(attributedString: NSMutableAttributedString)
}

public class BaseTheme: NSObject, Theme {
	static let encoder = JSONEncoder()
	static let decoder = JSONDecoder()
	
	var themeType: ThemeType { return self is SyntaxTheme ? .syntax : .output }
	
	private enum MyKeys: String, CodingKey {
		case name
	}
	
	public init(name: String) {
		self.name = name
		super.init()
		fileUrl = BaseTheme.themesPath(type: themeType, builtin: false)
			.appendingPathComponent(UUID().uuidString)
			.appendingPathExtension("json")
		DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(1000), execute: { self.saveIngoringError() })
	}
	
	public required init(from decoder: Decoder) throws {
		name = ""
//		let container = try decoder.container(keyedBy: MyKeys.self)
//		name = try container.decode(String.self, forKey: .name)
	}
	
	public func encode(to encoder: Encoder) throws {
		// all properties should be encoded by subclass
	}
	
	/// saves user editable theme to disk.
	public func save() throws {
		guard !isBuiltin else { throw ThemeError.notEditable }
		guard let url = fileUrl else { fatalError("why is there no url?") }
		let data = try BaseTheme.encoder.encode(self)
		try data.write(to: url)
		dirty = false
	}
	
	private func saveIngoringError() {
		do {
			try save()
		} catch {
			Log.error("error saving theme: \(error)", .core)
		}
	}
	
	public override var description: String { return "Theme \(name)" }
	
	/// map the static AttributeName to a non-static property so type name is not required to reference it
	public let attributeName: NSAttributedString.Key = NSAttributedString.Key("rc2.BaseTheme")
	
	public var allProperties: [ThemeProperty] {
		if type(of: self) == SyntaxTheme.self { return SyntaxThemeProperty.allProperties }
		return OutputThemeProperty.allProperties
	}
	
	public var name: String {
		willSet { guard !isBuiltin else { fatalError("can't edit name of builtin theme") } }
		didSet { if fileUrl != nil { saveIngoringError() } }
	}
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
	
	public subscript(key: ThemeProperty) -> PlatformColor? {
		get {
			return color(for: key)
		}
		set (newValue) {
			guard !isBuiltin else { fatalError("builtin themes are not editable") }
			guard let newValue = newValue else { fatalError("theme colors cannot be nil") }
			if let syntax = self as? SyntaxTheme, let prop = key as? SyntaxThemeProperty {
				guard syntax[prop] != newValue else { return }
				syntax[prop] = newValue
				dirty = true
				NotificationCenter.default.post(name: .SyntaxThemeModified, object: self)
			} else if let output = self as? OutputTheme, let prop = key as? OutputThemeProperty {
				guard output[prop] != newValue else { return }
				output[prop] = newValue
				dirty = true
				NotificationCenter.default.post(name: .OutputThemeModified, object: self)
			} else {
				Log.warn("unknown theme property \(key.localizedDescription)", .core)
			}
		}
	}

	/// returns the url to the theme file if builtin, the user dir if not builtin
	private static func themesPath(type: ThemeType, builtin: Bool) -> URL {
		let dirName: String
		switch type {
		case .syntax: dirName = "SyntaxThemes"
		case .output: dirName = "OutputThemes"
		}
		if builtin {
			/// at some point in Mojhave Budle.url(forResource) started percent encoding the superscript in the app title. This fixes that
			guard let rawPath = Bundle(for: ThemeManager.self).url(forResource: dirName, withExtension: "json"),
				let path = rawPath.path.removingPercentEncoding
			else { fatalError("failed to find themes") }
			return URL(fileURLWithPath: path)
		}
		// swiftlint:disable:next force_try
		return try! AppInfo.subdirectory(type: .applicationSupportDirectory, named: dirName)
	}
	
	static public func loadThemes<T: BaseTheme>() -> [T] {
		let ttype: ThemeType = T.self == SyntaxTheme.self ? .syntax : .output
		var themes: [T] = loadBuiltinThemes(from: themesPath(type: ttype, builtin: true))
		var urls = [URL]()
		do {
			urls = try FileManager.default.contentsOfDirectory(at: themesPath(type: ttype, builtin: false), includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
		} catch {
			Log.warn("error getting user themes: \(error)", .core)
			return themes
		}
		urls.forEach { aFile in
			guard aFile.pathExtension == "json" else { return }
			do {
				let data = try Data(contentsOf: aFile)
				let theme: T = try decoder.decode(T.self, from: data)
				theme.isBuiltin = false
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
			guard let path = url.path.removingPercentEncoding, let str = try? String(contentsOfFile: path), let data = str.data(using: .utf8)
				else { fatalError() }
			let themes: [T] = try decoder.decode([T].self, from: data).sorted(by: { $0.name < $1.name })
			themes.forEach { $0.isBuiltin = true }
			return themes
		} catch {
			fatalError("failed to decode builtin themes \(error)")
		}
	}
	
	/// Updates the attributed string so its attributes use this theme
	///
	/// - Parameter attributedString: The string whose attributes will be updated
	public func update(attributedString: NSMutableAttributedString) {
		fatalError("subclass must implement")
	}
}
