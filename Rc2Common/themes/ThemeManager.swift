//
//  ThemeManager.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import ReactiveSwift
import SwiftyUserDefaults
import MJLLogger

fileprivate extension DefaultsKeys {
	static let activeOutputTheme = DefaultsKey<OutputTheme?>("rc2.activeOutputTheme")
	static let activeSyntaxTheme = DefaultsKey<SyntaxTheme?>("rc2.activeSyntaxTheme")
}

enum ThemeError: Error {
	case notEditable
}

/// wraps the information about a type of theme to allow it to be used generically
public class ThemeWrapper<T: Theme> {
	public var themes: [T] { return getThemes() }
	public var selectedTheme: T { return getSelectedTheme() }
	public var builtinThemes: [T] { return themes.filter { $0.isBuiltin } }
	public var userThemes: [T] { return themes.filter { !$0.isBuiltin } }
	
	private var getThemes: () -> [T]
	private var getSelectedTheme: () -> T
	
	public init() {
		// swiftlint:disable force_cast
		if T.self == OutputTheme.self {
			getThemes = { return ThemeManager.shared.outputThemes as! [T] }
			getSelectedTheme = { return ThemeManager.shared.activeOutputTheme.value as! T }
		} else {
			getThemes = { return ThemeManager.shared.syntaxThemes as! [T] }
			getSelectedTheme = { return ThemeManager.shared.activeSyntaxTheme.value as! T }
		}
		// swiftlint:enable force_cast
	}
}

public class ThemeManager {
	public static let shared = ThemeManager()
	
	public var outputThemes: [OutputTheme] { return _outputThemes }
	public var syntaxThemes: [SyntaxTheme] { return _syntaxThemes }
	
	private var _outputThemes = [OutputTheme]()
	private var _syntaxThemes = [SyntaxTheme]()
	
	public let activeOutputTheme: MutableProperty<OutputTheme>!
	public let activeSyntaxTheme: MutableProperty<SyntaxTheme>!

	/// sets the active theme based on the type of theme passed as an argument
	public func setActive<T: Theme>(theme: T) {
		if let otheme = theme as? OutputTheme {
			activeOutputTheme.value = otheme
		} else if let stheme = theme as? SyntaxTheme {
			activeSyntaxTheme.value = stheme
		} else {
			fatalError("invalid theme")
		}
	}
	
	@objc private func syntaxThemeChanged(_ note: Notification) {
		guard let theme = note.object as? SyntaxTheme else { return }
		if activeSyntaxTheme.value.dirty {
			do {
				try activeSyntaxTheme.value.save()
			} catch {
				Log.error("error saving theme: \(error)", .core)
			}
		}
		activeSyntaxTheme.value = theme
	}
	
	@objc private func outputThemeChanged(_ note: Notification) {
		guard let theme = note.object as? OutputTheme else { return }
		if theme != activeOutputTheme.value, activeOutputTheme.value.dirty {
			do {
				try activeOutputTheme.value.save()
			} catch {
				Log.error("error saving theme: \(error)", .core)
			}
		}
		activeOutputTheme.value = theme
	}
	
	/// returns a duplicate of theme with a unique name that has already been inserted in the correct array
	public func duplicate<T: Theme>(theme: T) -> T {
		let currentNames = existingNames(theme)
		let baseName = "\(theme.name) copy"
		var num = 0
		var curName = baseName
		while currentNames.contains(curName) {
			num += 1
			curName = baseName + " \(num)"
		}
		let newTheme = clone(theme: theme, name: curName)
		setActive(theme: newTheme)
		return newTheme
	}
	
	/// clone theme by force casting due to limitation in swift type system
	private func clone<T: Theme>(theme: T, name: String) -> T {
		// swiftlint:disable force_cast
		if let outputTheme = theme as? OutputTheme {
			let copy = outputTheme.duplicate(name: name) as! T
			_outputThemes.append(copy as! OutputTheme)
			return copy
		} else if let syntaxTheme = theme as? SyntaxTheme {
			let copy = syntaxTheme.duplicate(name: name) as! T
			_syntaxThemes.append(copy as! SyntaxTheme)
			return copy
		}
		// swiftlint:enable force_try
		fatalError()
	}
	
	/// returns array of names of existing themes of the same type as instance
	private func existingNames<T: Theme>(_ instance: T) -> [String] {
		if instance is OutputTheme {
			return _outputThemes.map { $0.name }
		} else if instance is SyntaxTheme {
			return _syntaxThemes.map { $0.name }
		}
		fatalError()
	}
	
	private init() {
		_syntaxThemes = BaseTheme.loadThemes()
		_outputThemes = BaseTheme.loadThemes()
		let activeSyntax = ThemeManager.findDefaultSyntaxTheme(in: _syntaxThemes)
		activeSyntaxTheme = MutableProperty(activeSyntax)
		let activeOutput = ThemeManager.findDefaultOutputTheme(in: _outputThemes)
		activeOutputTheme = MutableProperty(activeOutput)
		
		NotificationCenter.default.addObserver(self, selector: #selector(syntaxThemeChanged(_:)), name: .SyntaxThemeModified, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(outputThemeChanged(_:)), name: .OutputThemeModified, object: nil)
	}
	
	private static func findDefaultOutputTheme(in array: [OutputTheme]) -> OutputTheme {
		if let theme: OutputTheme = Defaults[.activeOutputTheme] {
			return theme
		}
		//look for one named default
		if let defaultTheme = array.first(where: { $0.name == "Default" }) {
			return defaultTheme
		}
		return OutputTheme.defaultTheme as! OutputTheme
	}

	private static func findDefaultSyntaxTheme(in array: [SyntaxTheme]) -> SyntaxTheme {
		if let theme: SyntaxTheme = Defaults[.activeSyntaxTheme] {
			return theme
		}
		//look for one named default
		if let defaultTheme = array.first(where: { $0.name == "Default" }) {
			return defaultTheme
		}
		return SyntaxTheme.defaultTheme as! SyntaxTheme
	}

}
