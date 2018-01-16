//
//  HTMLStringTests.swift
//  ClientCoreTests
//
//  Created by Mark Lilback on 1/12/18.
//  Copyright © 2018 Rc2. All rights reserved.
//

import XCTest
@testable import ClientCore

class HTMLStringTests: XCTestCase {
	func testBold() {
		let html = "1. <b>foo</b>."
		let htmlStr = HTMLString(text: html)
		let attrStr = htmlStr.attributedString()
		XCTAssertEqual("1. foo.", attrStr.string)
	}

	func testItalic() {
		let html = "1. <i>foo</i>."
		let htmlStr = HTMLString(text: html)
		let attrStr = htmlStr.attributedString()
		XCTAssertEqual("1. foo.", attrStr.string)
	}

	func testColor() {
		let hexColor = "FF000F"
		let html = "1. <color hex=\"\(hexColor)\">foo</color>."
		let htmlStr = HTMLString(text: html)
		let attrStr = htmlStr.attributedString()
		XCTAssertEqual("1. foo.", attrStr.string)
		var range = NSRange()
		let color = attrStr.attribute(.foregroundColor, at: 5, effectiveRange: &range) as? NSColor
		XCTAssertNotNil(color)
		XCTAssertEqual(hexColor, color?.hexString)
	}

	func testInvalidColorAttrName() {
		let html = "1. <color name=\"purple\">foo</color>."
		let htmlStr = HTMLString(text: html)
		let attrStr = htmlStr.attributedString()
		XCTAssertEqual("1. foo.", attrStr.string)
		var range = NSRange()
		let color = attrStr.attribute(.foregroundColor, at: 5, effectiveRange: &range)
		XCTAssertNil(color)
	}
	
	func testMultiple() {
		let html = "1. <i>foo</i> <b>bar</b>."
		let htmlStr = HTMLString(text: html)
		let attrStr = htmlStr.attributedString()
		
		XCTAssertEqual("1. foo bar.", attrStr.string)
		var range = NSRange()
		let font = attrStr.attribute(.font, at: 5, effectiveRange: &range) as? NSFont
		XCTAssertNotNil(font)
		let traits = NSFontTraitMask(rawValue: UInt(font!.fontDescriptor.symbolicTraits.rawValue))
		XCTAssertTrue(traits.contains(.italicFontMask))
		let bfont = attrStr.attribute(.font, at: 8, effectiveRange: &range) as? NSFont
		XCTAssertNotNil(bfont)
		let btraits = NSFontTraitMask(rawValue: UInt(bfont!.fontDescriptor.symbolicTraits.rawValue))
		XCTAssertTrue(btraits.contains(.boldFontMask))
	}
}
