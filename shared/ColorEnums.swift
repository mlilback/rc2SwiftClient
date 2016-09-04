//
//  ColorEnums.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import ClientCore

enum OutputColors: String {
	case Input, Help, Status, Error, Note, Log
	
	static let allValues = [Input, Help, Status, Error, Note, Log]
	
	static func colorMap() -> [OutputColors:PlatformColor] {
		let oldDict = NSUserDefaults.standardUserDefaults().dictionaryForKey(PrefKeys.OutputColors) as! Dictionary<String,String>
		let outputColors = oldDict.reduce([OutputColors:PlatformColor]()) { (dict, pair) in
			var aDict = dict
			aDict[OutputColors(rawValue: pair.0)!] = PlatformColor.colorWithHexString(pair.1)
			return aDict
		}
		return outputColors
	}
}

enum SyntaxColors: String {
	case Comment, Keyword, Function, Quote, Symbol, CodeBackground, InlineBackground, EquationBackground
	
	static let allValues = [Comment, Keyword, Function, Quote, Symbol, CodeBackground, InlineBackground, EquationBackground]
}
