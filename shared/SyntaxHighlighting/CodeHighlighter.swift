//
//  CodeHighlighter
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

enum SyntaxColor: String {
	case Comment, Keyword, Function, Quote, Symbol, CodeBackground, InlineBackground, EquationBackground
	
	static let allValues = [Comment, Keyword, Function, Quote, Symbol, CodeBackground, InlineBackground, EquationBackground]
}

protocol CodeHighlighter: NSObjectProtocol {
	var colorMap:[SyntaxColor:PlatformColor] { get }
	
	func highlightText(content:NSMutableAttributedString, range:NSRange)
}
