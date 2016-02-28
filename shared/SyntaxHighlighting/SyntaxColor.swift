//
//  SyntaxColor.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

enum SyntaxColor: String {
	case Comment, Keyword, Function, Quote, Symbol, CodeBackground, InlineBackground, EquationBackground
	
	static let allValues = [Comment, Keyword, Function, Quote, Symbol, CodeBackground, InlineBackground, EquationBackground]
}

struct SyntaxColorMap {
	static var standardMap:SyntaxColorMap = {
		let srcMap = NSUserDefaults.standardUserDefaults().objectForKey(RCodeHighlighterColors) as! [String:String]
		var dict: [SyntaxColor:PlatformColor] = [:]
		for (key,value) in srcMap {
			try! dict[SyntaxColor(rawValue:key)!] = PlatformColor(hex:value)
		}
		return SyntaxColorMap(colorDict: dict)
	}()
	
	private var colorMap:[SyntaxColor:PlatformColor] = [:]
	
	init(colorDict:[SyntaxColor:PlatformColor]) {
		self.colorMap = colorDict;
	}
	
	subscript(key:SyntaxColor) -> PlatformColor? {
		get { return colorMap[key] }
		set { colorMap[key] = newValue }
	}
}
