//
//  SessionEditor.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import ClientCore
import SwiftyUserDefaults

class SessionEditor: TextViewWithContextualMenu {
	var wordWrapEnabled: Bool { return textContainer!.widthTracksTextView }
	
	override var typingAttributes: [NSAttributedStringKey : Any] {
		get { return super.typingAttributes }
		set { var attrs = newValue; attrs.removeValue(forKey: ChunkAttrName); super.typingAttributes = attrs }
	}

	override func awakeFromNib() {
		super.awakeFromNib()
		usesFindBar = true
		isAutomaticSpellingCorrectionEnabled = false
		isAutomaticQuoteSubstitutionEnabled = false
		isAutomaticDashSubstitutionEnabled = false
		
	}
	
	var rangeOfAllText: NSRange {
		return NSRange(location: 0, length: textStorage!.length)
	}
	
	func moveCursorToNextNonBlankLine() {
		let contents = string
		var lastLocation: String.Index = contents.endIndex
		while true {
			moveToEndOfParagraph(nil)
			moveRight(nil)
			guard let selRange = selectedRange().toStringRange(contents) else { break }
			let nextLineRange = string.lineRange(for: selRange)
			guard nextLineRange.lowerBound > lastLocation else { break } //end of line
			lastLocation = nextLineRange.lowerBound
			let nextStr = string.substring(with: nextLineRange).trimmingCharacters(in: .whitespacesAndNewlines)
			if nextStr.characters.count > 0 {
				//end of string
				break
			}
		}
	}
	
	//with this version, if the close paren was at the end of the line, the blank space at the end of the line was colored, too. this did not happen in the old version of the client with similar code in objective-c. so we don't flash the close paren they just typed
	override func insertText(_ aString: Any, replacementRange: NSRange) {
		super.insertText(aString, replacementRange: replacementRange)
		guard let str = aString as? NSString else { return }
		guard str == ")" else { return }
		let openLoc = findMatchingParenthesis(selectedRange().location - 2, str: str)
		guard openLoc != NSNotFound else { return }
//		let curLoc = selectedRange()
		//flash the inserted character and matching opening character
//		let closeRange = NSMakeRange(curLoc.location, 1)
		let openRange = NSRange(location: openLoc, length: 1)
		let color = PlatformColor(hexString: "888888")!
//		layoutManager?.addTemporaryAttribute(NSBackgroundColorAttributeName, value: color, forCharacterRange: closeRange)
		layoutManager?.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: openRange)
		//FIXME: code smell
		delay(0.1) {
//			self.layoutManager?.removeTemporaryAttribute(NSBackgroundColorAttributeName, forCharacterRange: closeRange)
			self.layoutManager?.removeTemporaryAttribute(.backgroundColor, forCharacterRange: openRange)
		}
	}
	
	//can't figure out an easy was to compare with a character constant '(', so use ascii code for comparison
	func findMatchingParenthesis(_ closeLocation: Int, str: NSString) -> Int {
		var stackCount = 0
		var curLocation = closeLocation
		let contentStr = textStorage!.string as NSString
		while curLocation > 0 {
			let prospectiveChar = contentStr.character(at: curLocation)
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

	func findMatchingParenthesisNative(_ closeLocation: Int, str: String) -> Int {
		var stackCount = 0
		var curLocation = str.characters.index(str.startIndex, offsetBy: closeLocation)
		while str.characters.distance(from: str.startIndex, to: curLocation) > 0 {
			if str[curLocation] == Character("(") {
				if stackCount == 0 { return str.characters.distance(from: str.startIndex, to: curLocation) }
				stackCount -= 1
			} else if str[curLocation] == Character(")") {
				stackCount += 1
				guard stackCount >= 0 else { return NSNotFound }
			}
			curLocation = str.characters.index(curLocation, offsetBy: -1)
		}
		return NSNotFound
	}
	
	@IBAction func toggleWordWrap(_ sender: AnyObject?) {
		let wordWrap = !wordWrapEnabled
		let defaults = UserDefaults.standard
		defaults[.wordWrapEnabled] = wordWrap
		adjustWordWrap(wordWrap)
	}
	
	func adjustWordWrap(_ wrap: Bool) {
		let container = textContainer!
		if wrap {
			container.widthTracksTextView = false
			container.containerSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
			isHorizontallyResizable = true
		} else {
			container.widthTracksTextView = true
			container.containerSize = CGSize(width: 200, height: CGFloat.greatestFiniteMagnitude)
		}
		didChangeText()
		enclosingScrollView?.verticalRulerView?.needsDisplay = true
	}
}
