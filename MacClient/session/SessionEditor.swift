//
//  SessionEditor.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

class SessionEditor: TextViewWithContextualMenu {
	var wordWrapEnabled:Bool { return textContainer!.widthTracksTextView }
	
	override func awakeFromNib() {
		super.awakeFromNib()
		usesFindBar = true
		automaticSpellingCorrectionEnabled = false
		automaticQuoteSubstitutionEnabled = false
		automaticDashSubstitutionEnabled = false
		
	}
	
	var rangeOfAllText:NSRange {
		return NSMakeRange(0, textStorage!.length)
	}
	
	//with this version, if the close paren was at the end of the line, the blank space at the end of the line was colored, too. this did not happen in the old version of the client with similar code in objective-c. so we don't flash the close paren they just typed
	override func insertText(aString: AnyObject, replacementRange: NSRange) {
		super.insertText(aString, replacementRange: replacementRange)
		guard let str = aString as? NSString else { return }
		guard str == ")" else { return }
		let openLoc = findMatchingParenthesis(selectedRange().location - 2, str: str)
		guard openLoc != NSNotFound else { return }
//		let curLoc = selectedRange()
		//flash the inserted character and matching opening character
//		let closeRange = NSMakeRange(curLoc.location, 1)
		let openRange = NSMakeRange(openLoc, 1)
		let color = try! PlatformColor(hex: "888888")
//		layoutManager?.addTemporaryAttribute(NSBackgroundColorAttributeName, value: color, forCharacterRange: closeRange)
		layoutManager?.addTemporaryAttribute(NSBackgroundColorAttributeName, value: color, forCharacterRange: openRange)
		delay(0.1) {
//			self.layoutManager?.removeTemporaryAttribute(NSBackgroundColorAttributeName, forCharacterRange: closeRange)
			self.layoutManager?.removeTemporaryAttribute(NSBackgroundColorAttributeName, forCharacterRange: openRange)
		}
	}
	
	//can't figure out an easy was to compare with a character constant '(', so use ascii code for comparison
	func findMatchingParenthesis(closeLocation:Int, str:NSString) -> Int {
		var stackCount = 0
		var curLocation = closeLocation
		let contentStr = textStorage!.string as NSString
		while curLocation > 0 {
			let prospectiveChar = contentStr.characterAtIndex(curLocation)
			if prospectiveChar == 40 /* ( */ {
				if stackCount == 0 { return curLocation }
				stackCount -= 1
			} else if prospectiveChar == 41 /* ) */ {
				stackCount += 1
				guard stackCount >= 0 else { return NSNotFound }
			}
			curLocation -= 1
		}
		return NSNotFound
	}

	func findMatchingParenthesisNative(closeLocation:Int, str:String) -> Int {
		var stackCount = 0
		var curLocation = str.startIndex.advancedBy(closeLocation)
		while str.startIndex.distanceTo(curLocation) > 0 {
			if str[curLocation] == Character("(") {
				if stackCount == 0 { return str.startIndex.distanceTo(curLocation) }
				stackCount -= 1
			} else if str[curLocation] == Character(")") {
				stackCount += 1
				guard stackCount >= 0 else { return NSNotFound }
			}
			curLocation = curLocation.advancedBy(-1)
		}
		return NSNotFound
	}
	
	@IBAction func toggleWordWrap(sender:AnyObject?) {
		let wordWrap = !wordWrapEnabled
		let defaults = NSUserDefaults.standardUserDefaults()
		defaults.setBool(wordWrap, forKey: PrefKeys.WordWrapEnabled)
		adjustWordWrap(wordWrap)
	}
	
	func adjustWordWrap(wrap:Bool) {
		let container = textContainer!
		if wrap {
			container.widthTracksTextView = false
			container.containerSize = CGSizeMake(CGFloat.max, CGFloat.max)
			horizontallyResizable = true
		} else {
			container.widthTracksTextView = true
			container.containerSize = CGSizeMake(200, CGFloat.max)
		}
		didChangeText()
		enclosingScrollView?.verticalRulerView?.needsDisplay = true
	}
}
