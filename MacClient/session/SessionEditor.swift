//
//  SessionEditor.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import Rc2Common
import SwiftyUserDefaults

extension NSTextView {
	/// installs line number view as the vertical ruler
	func enableLineNumberView(ignoreHandler: (() -> Bool)? = nil) -> FontUser? {
		guard enclosingScrollView!.verticalRulerView == nil else { return nil }
		let lnv = LineNumberRulerView(scrollView: enclosingScrollView, orientation: .verticalRuler)
		enclosingScrollView!.verticalRulerView = lnv
		enclosingScrollView!.rulersVisible = true
		lnv.clientView = self
		lnv.shouldIgnoreNotifications = ignoreHandler
		return lnv
	}
}

@objc protocol SessionEditorDelegate: NSTextViewDelegate {
	/// Called before an insert from a pasteboard (paste, drop)
	/// - Parameters:
	///   - editor: the editor receiving the pasteboard
	///   - pasteboard: the pastedboard with the contents to be inserted
	///   - range: the range in the contents that will be replaced
	/// - Returns: true if the pasteboard should be inserted, false to abort
	@objc optional func shouldInsertFromPasteboard(_ editor: SessionEditor, pasteboard: NSPasteboard, range: NSRange) -> Bool
	
	/// called when data has been inserted from a pasteboard (paste,d&d)
	/// - Parameters:
	///   - editor: the SessionEditor/TextView
	///   - previousRange: the range that was replaced
	@objc optional func didInsertFromPasteboard(_ editor: SessionEditor, previousRange: NSRange)
}

class SessionEditor: TextViewWithContextualMenu {
	var wordWrapEnabled: Bool { return textContainer!.widthTracksTextView }
	var sessionEditorDelegate: SessionEditorDelegate? { return delegate as? SessionEditorDelegate }

	private var didSetup = false

	override func awakeFromNib() {
		super.awakeFromNib()
		guard !didSetup else { return }
		didSetup = true
		usesFindBar = true
		isAutomaticSpellingCorrectionEnabled = false
		isAutomaticQuoteSubstitutionEnabled = false
		isAutomaticDashSubstitutionEnabled = false
		textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
		textContainer?.widthTracksTextView = true
		isHorizontallyResizable = true
		isEditable = false
		if #available(macOS 10.14, *) {
			self.appearance = NSAppearance(named: .aqua)
		}
	}

	var rangeOfAllText: NSRange {
		return NSRange(location: 0, length: textStorage!.length)
	}

	// overriden so delegate can know when text is pasted/dropped
	override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
		let prevRange = rangeForUserTextChange
		guard sessionEditorDelegate?.shouldInsertFromPasteboard?(self, pasteboard: pboard, range: prevRange) ??  true else { return false }
		let result = super.readSelection(from: pboard, type: type)
		sessionEditorDelegate?.didInsertFromPasteboard?(self, previousRange: prevRange)
		return result
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
			let nextStr = string[nextLineRange].trimmingCharacters(in: .whitespacesAndNewlines)
			if nextStr.count > 0 {
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
		//flash the inserted character and matching opening character
		let openRange = NSRange(location: openLoc, length: 1)
		let color = PlatformColor(hexString: "888888")!
		layoutManager?.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: openRange)
		//FIXME: code smell
		delay(0.1) {
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
		var curLocation = str.index(str.startIndex, offsetBy: closeLocation)
		while str.distance(from: str.startIndex, to: curLocation) > 0 {
			if str[curLocation] == Character("(") {
				if stackCount == 0 { return str.distance(from: str.startIndex, to: curLocation) }
				stackCount -= 1
			} else if str[curLocation] == Character(")") {
				stackCount += 1
				guard stackCount >= 0 else { return NSNotFound }
			}
			curLocation = str.index(curLocation, offsetBy: -1)
		}
		return NSNotFound
	}

	@IBAction func toggleWordWrap(_ sender: Any?) {
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
