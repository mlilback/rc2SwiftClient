//
//  RmdDocumentTests.swift
//  SyntaxParsingTests
//
//  Created by Mark Lilback on 3/19/18.
//  Copyright © 2018 Rc2. All rights reserved.
//

import XCTest
@testable import SyntaxParsing

class RmdDocumentTests: XCTestCase {

	override func setUp() {
		super.setUp()
		// Put setup code here. This method is called before the invocation of each test method in the class.
	}
	
	override func tearDown() {
		// Put teardown code here. This method is called after the invocation of each test method in the class.
		super.tearDown()
	}

	func testInlineEquation() {
		let source = """
		Some doc text $\\frac{1}{n} \\sum_{i=i}^{n} x_{i} chunk5-eq,in$ was here
		"""
		var document: RmdDocument!
		XCTAssertNoThrow(document = try RmdDocument(contents: source, helpCallback: { _ in return false }))
		XCTAssertEqual(document.chunks.count, 1)
		guard let textChunk = document.chunks.first as? TextChunk else { XCTFail("not text chunk"); return }
		XCTAssertTrue(textChunk.contents.hasSuffix("here"))
		XCTAssertEqual(textChunk.inlineElements.count, 1)
		guard let inlineChunk = textChunk.inlineElements.first, let inlineEq = inlineChunk as? Equation else { XCTFail("failed to get inline chunk"); return }
		XCTAssertTrue(inlineEq.equationSource.starts(with: "\\f"))
		let strContents = textChunk.contents
		XCTAssertEqual(strContents, source)
	}

}
