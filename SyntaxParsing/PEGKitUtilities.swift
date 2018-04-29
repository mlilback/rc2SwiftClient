//
//  PEGKitUtilities.swift
//  ParserShell
//
//  Created by Alex Harner on 2018/03/10.
//  Copyright © 2018 Mark Lilback. All rights reserved.
//

import Foundation
import PEGKit

// Constants:
let hashChar = Int32("#".unicodeScalars.first!.value)
let lessChar = Int32("<".unicodeScalars.first!.value)
let percentChar = Int32("%".unicodeScalars.first!.value)
let backSlashChar = Int32("\\".unicodeScalars.first!.value)
let fwdSlashChar = Int32("/".unicodeScalars.first!.value)
let dQuoteChar = Int32("\"".unicodeScalars.first!.value)
let sQuoteChar = Int32("'".unicodeScalars.first!.value)

func setBaseTokenizer(_ tok: PKTokenizer) {
	tok.whitespaceState.reportsWhitespaceTokens = true
	tok.numberState.allowsScientificNotation = true	// good in general
	tok.commentState.reportsCommentTokens = true	
	tok.setTokenizerState(tok.quoteState, from:dQuoteChar, to:dQuoteChar)
}
