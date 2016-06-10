//
//  SyntaxColor.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

///values representing the possible token types that can have different colors mapped to them
public enum SyntaxColor: String {
	case Comment, Keyword, Function, Quote, Symbol, CodeBackground, InlineBackground, EquationBackground
	
	static let allValues = [Comment, Keyword, Function, Quote, Symbol, CodeBackground, InlineBackground, EquationBackground]
}

///A struct for mapping a SyntaxColor to a PlatformColor (NSColor, UIColor)
public struct SyntaxColorMap {
	///A singleton map loaded from user defaults Assumes a default map was installed (likely by the register domain).
	static var standardMap:SyntaxColorMap = {
		let srcMap = NSUserDefaults.standardUserDefaults().objectForKey(RCodeHighlighterColors) as! [String:String]
		var dict: [SyntaxColor:PlatformColor] = [:]
		for (key,value) in srcMap {
			try! dict[SyntaxColor(rawValue:key)!] = PlatformColor(hex:value)
		}
		return SyntaxColorMap(colorDict: dict)
	}()
	
	private var colorMap:[SyntaxColor:PlatformColor] = [:]
	
	///initializes a SyntaxColorMap
	/// - parameter colorDict: A dictionary of syntax colors mapped to platform colors
	init(colorDict:[SyntaxColor:PlatformColor]) {
		self.colorMap = colorDict;
	}
	
	/// maps a SyntaxColor to a PlatformColor
	subscript(key:SyntaxColor) -> PlatformColor? {
		get { return colorMap[key] }
		set { colorMap[key] = newValue }
	}
}
