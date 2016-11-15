//
//  ColorEnums.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import SwiftyUserDefaults

// MARK: Keys for UserDefaults
extension DefaultsKeys {
	static let outputColors = DefaultsKey<[String: Any]>("OutputColors")
}

public enum OutputColors: String {
	case Input, Help, Status, Error, Note, Log

	public static let allValues = [Input, Help, Status, Error, Note, Log]

	public static func colorMap() -> [OutputColors:PlatformColor] {
		guard let oldDict = UserDefaults.standard[.outputColors] as? [String: String] else {
			fatalError("failed to find defaults for output colors")
		}
		let outputColors = oldDict.reduce([OutputColors:PlatformColor]()) { (dict, pair) in
			var aDict = dict
			aDict[OutputColors(rawValue: pair.0)!] = PlatformColor.colorWithHexString(pair.1)
			return aDict
		}
		return outputColors
	}
}

public enum SyntaxColors: String {
	case Comment, Keyword, Function, Quote, Symbol, CodeBackground, InlineBackground, EquationBackground

	public static let allValues = [Comment, Keyword, Function, Quote, Symbol, CodeBackground, InlineBackground, EquationBackground]
}
