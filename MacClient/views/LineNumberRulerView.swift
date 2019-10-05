//
//  LineNumberRulerView.swift
//
//  Copyright ©2018 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import MJLLogger

class LineNumberRulerView: NSRulerView, FontUser {
	enum Errors: String, Error {
		case badRange
	}

	var shouldIgnoreNotifications: (() -> Bool)?

	var font: NSFont {
		didSet {
			needsDisplay = true
			textAttributes[.font] = font
		}
	}
	private var isLineInfoValid = false
	private var textAttributes = [NSAttributedString.Key: Any]()
	
	override init(scrollView: NSScrollView?, orientation: NSRulerView.Orientation) {
		font = NSFont.labelFont(ofSize: NSFont.systemFontSize(for: .mini))
		textAttributes[.foregroundColor] = NSColor.labelColor
		super.init(scrollView: scrollView, orientation: orientation)
	}
	
	required init(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
	
	var currentStorage: NSTextStorage? { return (self.clientView as? NSTextView)?.textStorage ?? nil }
	
	var lineRanges = [Range<String.Index>]()
	
	override var isFlipped: Bool { return true }
	
	override var clientView: NSView? {
		didSet {
			// need to be notified when the text changes
			let ncenter = NotificationCenter.default
			let note = NSTextStorage.didProcessEditingNotification
			ncenter.removeObserver(self, name: note, object: nil)
			guard let client = clientView as? NSTextView else { return }
			ncenter.addObserver(self, selector: #selector(didProcessEdit(_:)), name: note, object: client.textStorage)
			isLineInfoValid = false
		}
	}
	
	@objc func didProcessEdit(_ note: Notification) {
		if shouldIgnoreNotifications?() ?? false { return }
		self.needsDisplay = true
		isLineInfoValid = false
	}
	
	func updateLineInformation() {
		var ranges = [Range<String.Index>]()
		let contents = currentStorage?.string ?? ""
		// get the index of the start of each line
		contents.enumerateSubstrings(in: contents.fullRange, options: [.byLines, .substringNotRequired]) { (_, range, _, _) in
			ranges.append(range)
		}
		lineRanges = ranges
		isLineInfoValid = true
	
		// update thickness
		let numDigits = CGFloat(ranges.count > 0 ? ceil(log10(Double(ranges.count))) : 1)
		let digitSize = NSString("0").size(withAttributes: textAttributes)
		self.ruleThickness =  max(ceil(digitSize.width * numDigits + 8.0), 10.0)
	}
	
	override func viewWillDraw() {
		super.viewWillDraw()
		if !isLineInfoValid {
			updateLineInformation()
		}
	}
	
	/// calls fatalError() if invalid index
	func lineIndexFor(characterIndex cidx: String.Index) throws -> Int {
		for (idx, range) in lineRanges.enumerated() {
			if range.contains(cidx) { return idx }
			if range.lowerBound == cidx && range.upperBound == cidx { return idx }
		}
		throw Errors.badRange
	}
	
	override func drawHashMarksAndLabels(in dirtyRect: NSRect) {
		// draw background
		NSColor.controlBackgroundColor.set()
		dirtyRect.fill(using: .copy)
		
		// draw border line
		let borderRect: NSRect
		switch orientation {
		case .verticalRuler:
			borderRect = NSRect(x: NSMaxX(bounds) - 1.0, y: 0, width: 1, height: bounds.height)
		case .horizontalRuler:
			borderRect = NSRect(x: 0, y: 0, width: bounds.width, height: 1.0)
		}
		if needsToDraw(borderRect) {
			NSColor.controlBackgroundColor.shadow(withLevel: 0.4)?.set()
			borderRect.fill(using: .copy)
		}
		
		// no more drawing unless we have a text view
		guard let client = clientView as? NSTextView else { return }
		
		// draw the line numbers
		guard let storage = client.textStorage, let container = client.textContainer,
			let lm = client.layoutManager, let scroll = scrollView
			else {
				Log.warn("can't draw with complete text heirarcy")
				return
			}
		let contents = storage.string
		let visibleRect = scroll.contentView.bounds
		let inset = client.textContainerInset
		let rightMostDrawableLocation = borderRect.minX
		
		let visGlyphNSRange = lm.glyphRange(forBoundingRect: visibleRect, in: container)
		let visCharNSRange = lm.characterRange(forGlyphRange: visGlyphNSRange, actualGlyphRange: nil)
		guard let visibleCharRange = Range(visCharNSRange, in: contents) else { return }
		var lastLinePositionY = CGFloat(-1.0)
		// for some reason, visibleCHar arange does not implement Stridable, and can't be used in a for..in loop. But substrings are just slices, so there is no real overhead to using one for this
		let substr = contents[visibleCharRange]
		
		var charIdx = substr.startIndex
		while charIdx != substr.endIndex {
			// if there is no line for the character, something is seriously wrong
			guard let lineNumber = try? lineIndexFor(characterIndex: charIdx)
			else {
				Log.error("a character not in line should be impossible", .app)
				charIdx = substr.endIndex
				break
			}
			let grange = lm.glyphRange(forCharacterRange: NSRange(lineRanges[lineNumber], in: contents), actualCharacterRange: nil)
			let brect = lm.boundingRect(forGlyphRange: grange, in: container)
			let lineStr = String(lineNumber + 1) as NSString
			let lineStrSize = lineStr.size(withAttributes: textAttributes)
			let lineStrRect = NSRect(x: rightMostDrawableLocation - lineStrSize.width - 2.0,
									 y: brect.minY + inset.height,
									 width: lineStrSize.width,
									 height: lineStrSize.height)
			if needsToDraw(lineStrRect.insetBy(dx: -4.0, dy: -4.0)) && lineStrRect.minY != lastLinePositionY {
				lineStr.draw(with: lineStrRect, options: .usesLineFragmentOrigin, attributes: textAttributes)
			}
			lastLinePositionY = lineStrRect.minY
			// This is a workaround for an Apple bug. The docs (and open source version) make the 3 pointers optional, as it a performance boost to not have to calcuate them all. feedback filed as FB7347946
			var startIdx: String.Index = contents.startIndex
			var endIdx: String.Index = contents.startIndex
			var endC: String.Index = contents.startIndex
			contents.getLineStart(&startIdx, end: &endIdx, contentsEnd: &endC, for: charIdx...charIdx)
			charIdx = endIdx
		}
	}
}

extension StringProtocol {
	func indexDistance(from: String.Index) -> Int {
		return distance(from: startIndex, to: from)
	}
	func rangeDetails(_ range: Range<String.Index>) -> String? {
		return "\(indexDistance(from: range.lowerBound))...\(indexDistance(from: range.upperBound))";
	}
}
