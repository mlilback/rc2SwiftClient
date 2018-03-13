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

func setBaseTokenizer(_ tok: PKTokenizer) {
	tok.whitespaceState.reportsWhitespaceTokens = true
	tok.numberState.allowsScientificNotation = true	// good in general
	tok.commentState.reportsCommentTokens = true
	let quoteChar = Int32("\"".unicodeScalars.first!.value)
	tok.setTokenizerState(tok.quoteState, from:quoteChar, to:quoteChar)
}
