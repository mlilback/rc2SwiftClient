//
//  ColorEnums.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

enum OutputColors: String {
	case Input, Help, Status, Error, Note, Log
	
	static let allValues = [Input, Help, Status, Error, Note, Log]
}

enum SyntaxColors: String {
	case Comment, Keyword, Function, Quote, Symbol, CodeBackground, InlineBackground, EquationBackground
	
	static let allValues = [Comment, Keyword, Function, Quote, Symbol, CodeBackground, InlineBackground, EquationBackground]
}
