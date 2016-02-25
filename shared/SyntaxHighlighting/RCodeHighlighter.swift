//
//  RCodeHighlighter
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

let RCodeHighlighterColors = "RCodeHighlighterColors"

class RCodeHighlighter: NSObject, CodeHighlighter {
	///loads RCodeHighlighterColors [String:String(hexcode)] from NSUserDefaults
	let colorMap:[SyntaxColor:PlatformColor]
	
	///will cause runtime exception if RCodeHighlighterColors not in user defaults with string keys matching SyntaxColor enum rawValues and color hex strings for values
	override init() {
		let srcMap = NSUserDefaults.standardUserDefaults().objectForKey(RCodeHighlighterColors) as! [String:String]
		var dict: [SyntaxColor:PlatformColor] = [:]
		for (key,value) in srcMap {
			try! dict[SyntaxColor(rawValue:key)!] = PlatformColor(hex:value)
		}
		self.colorMap = dict
		super.init()
	}
	
	func highlightText(content:NSMutableAttributedString, range:NSRange) {
		
	}
}
