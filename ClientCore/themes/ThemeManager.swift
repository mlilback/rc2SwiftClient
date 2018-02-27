//
//  ThemeManager.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Freddy
import ReactiveSwift
import SwiftyUserDefaults

fileprivate extension DefaultsKeys {
	static let activeOutputTheme = DefaultsKey<JSON?>("rc2.activeOutputTheme")
	static let activeSyntaxTheme = DefaultsKey<JSON?>("rc2.activeSyntaxTheme")
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
		activeSyntaxTheme.value = theme
	}
	
	@objc private func outputThemeChanged(_ note: Notification) {
		guard let theme = note.object as? OutputTheme else { return }
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
		let activeSyntax = ThemeManager.findDefaultTheme(in: _syntaxThemes, key: .activeSyntaxTheme)
		activeSyntaxTheme = MutableProperty(activeSyntax)
		let activeOutput = ThemeManager.findDefaultTheme(in: _outputThemes, key: .activeOutputTheme)
		activeOutputTheme = MutableProperty(activeOutput)
		
		NotificationCenter.default.addObserver(self, selector: #selector(syntaxThemeChanged(_:)), name: .SyntaxThemeModified, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(outputThemeChanged(_:)), name: .OutputThemeModified, object: nil)
	}
	
	private static func findDefaultTheme<T: BaseTheme>(in array: [T], key: DefaultsKey<JSON?>) -> T {
		if let json = UserDefaults.standard[key],
			let theme = try? json.decode(type: T.self)
		{
			return theme
		}
		//look for one named default
		if let defaultTheme = array.first(where: { $0.name == "Default" }) {
			return defaultTheme
		}
		if T.self == SyntaxTheme.self {
			return SyntaxTheme.defaultTheme as! T
		} else if T.self == OutputTheme.self {
			return OutputTheme.defaultTheme as! T
		}
		fatalError()
	}
	
}
