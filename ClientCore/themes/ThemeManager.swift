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
	
	public func getActive<T: Theme>() -> T {
		if T.Type.self == type(of: OutputTheme.self) {
			return activeOutputTheme.value as! T // swiftlint:disable:this force_cast
		}
		return activeSyntaxTheme.value as! T // swiftlint:disable:this force_cast
	}
	
	public func setActive<T: Theme>(theme: T) {
		if let otheme = theme as? OutputTheme {
			activeOutputTheme.value = otheme
		} else if let stheme = theme as? SyntaxTheme {
			activeSyntaxTheme.value = stheme
		} else {
			fatalError("invalid theme")
		}
	}
	
	private init() {
		let synThemes = ThemeManager.loadSyntaxThemes()
		let activeTheme = ThemeManager.findDefaultTheme(in: synThemes, key: .activeSyntaxTheme)
		_syntaxThemes = synThemes
		activeSyntaxTheme = MutableProperty(activeTheme)

		let outThemes = ThemeManager.loadOutputThemes()
		let activeOut = ThemeManager.findDefaultTheme(in: outThemes, key: .activeOutputTheme)
		_outputThemes = outThemes
		activeOutputTheme = MutableProperty(activeOut)
	}
	
	private static func loadSyntaxThemes() -> [SyntaxTheme] {
		var themes = [SyntaxTheme]()
		let systemUrl = Bundle.main.url(forResource: "syntaxThemes", withExtension: "json")!
		// swiftlint:disable:next force_try
		let userUrl = try! AppInfo.subdirectory(type: .applicationSupportDirectory, named: "SyntaxThemes")
		themes.append(contentsOf: SyntaxTheme.loadThemes(from: systemUrl, builtin: true))
		themes.append(contentsOf: SyntaxTheme.loadThemes(from: userUrl, builtin: false))
		return themes
	}

	private static func loadOutputThemes() -> [OutputTheme] {
		var output = [OutputTheme]()
		let systemUrl = Bundle.main.url(forResource: "outputThemes", withExtension: "json")!
		// swiftlint:disable:next force_try
		let userUrl = try! AppInfo.subdirectory(type: .applicationSupportDirectory, named: "OutputThemes")
		output.append(contentsOf: OutputTheme.loadThemes(from: systemUrl, builtin: true))
		output.append(contentsOf: OutputTheme.loadThemes(from: userUrl, builtin: false))
		return output
	}

	private static func findDefaultTheme<T: Theme>(in array: [T], key: DefaultsKey<JSON?>) -> T {
		if let json = UserDefaults.standard[key],
			let theme = try? json.decode(type: T.self)
		{
			return theme
		}
		//look for one named default
		if let defaultTheme = array.first(where: { $0.name == "Default" }) {
			return defaultTheme
		}
		return T.defaultTheme
	}
	
}
