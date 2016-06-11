//
//  SyntaxParserTests
//  SwiftClient
//
//  Created by Mark Lilback on 2/29/16.
//  Copyright © 2016 Rc2. All rights reserved.
//

import XCTest
@testable import MacClient

class SyntaxParserTests: XCTestCase {
	var storage:NSTextStorage!
	var parser:SyntaxParser!
	
	override func setUp() {
		super.setUp()
		storage = NSTextStorage()
	}
	
	override func tearDown() {
		super.tearDown()
	}

	func loadStorageWith(filename:String, suffix:String) {
		parser = SyntaxParser.parserWithTextStorage(storage, fileType: FileType.fileTypeWithExtension(suffix)!)
		let fileUrl = NSBundle(forClass: self.dynamicType).URLForResource(filename, withExtension: suffix, subdirectory: "testFiles")!
		let contents = try! String(contentsOfURL: fileUrl, encoding: NSUTF8StringEncoding)
		storage.replaceCharactersInRange(NSMakeRange(0, storage.string.utf8.count), withString: contents)
	}
	
	func testChunkBreaks() {
		//storage must be non-empty and not the same length as the range
		// we are testing. "foo" should do
		storage.appendAttributedString(NSAttributedString(string: "foo"))
		let chunks = [
			DocumentChunk(chunkType: .Equation, chunkNumber: 1),
			DocumentChunk(chunkType: .Documentation, chunkNumber: 2),
			DocumentChunk(chunkType: .RCode, chunkNumber: 3)
		]
		chunks[0].parsedRange = NSMakeRange(0, 10)
		chunks[1].parsedRange = NSMakeRange(10, 20)
		chunks[2].parsedRange = NSMakeRange(30, 30)
		parser = SyntaxParser.parserWithTextStorage(storage, fileType: FileType.fileTypeWithExtension("Rmd")!)
		parser.chunks = chunks
		//test empty range which should return first chunk
		var results = parser.chunksForRange(NSMakeRange(0, 0))
		XCTAssertEqual(results.count, 1)
		XCTAssertEqual(results[0], chunks[0])
		//test with one matching chunk
		results = parser.chunksForRange(NSMakeRange(1, 1))
		XCTAssertEqual(results.count, 1)
		XCTAssertEqual(results[0], chunks[0])
		//test with 2 matching chunks
		results = parser.chunksForRange(NSMakeRange(9, 4))
		XCTAssertEqual(results.count, 2)
		XCTAssertEqual(results[0], chunks[0])
		XCTAssertEqual(results[1], chunks[1])
		//test empty range at end of first chunk (i.e. deleting at border)
		results = parser.chunksForRange(NSMakeRange(10, 0))
		XCTAssertEqual(results.count, 1)
		XCTAssertEqual(results[0], chunks[0])
		//test inserting at start of second chunk
		results = parser.chunksForRange(NSMakeRange(10, 1))
		XCTAssertEqual(results.count, 1)
		XCTAssertEqual(results[0], chunks[1])
		
	}
	
	func testSweave1() {
		loadStorageWith("syntax1", suffix:"Rnw")
		parser.parse()
		XCTAssertEqual(parser.chunks.count, 5)
		XCTAssertEqual(parser.chunks[0].type, ChunkType.Documentation)
		XCTAssertEqual(parser.chunks[1].type, ChunkType.RCode)
		XCTAssertEqual(parser.chunks[2].type, ChunkType.Documentation)
		XCTAssertEqual(parser.chunks[3].type, ChunkType.RCode)
		XCTAssertEqual(parser.chunks[3].name, "fig=TRUE,echo=FALSE")
		XCTAssertEqual(parser.chunks[4].type, ChunkType.Documentation)
	}
	
	func testMarkdown1() {
		loadStorageWith("syntax2", suffix:"Rmd")
		parser.parse()
		XCTAssertEqual(parser.chunks.count, 7)
		XCTAssertEqual(parser.chunks[0].type, ChunkType.Documentation)
		XCTAssertEqual(parser.chunks[1].type, ChunkType.Equation)
		XCTAssertEqual(parser.chunks[2].type, ChunkType.Documentation)
		XCTAssertEqual(parser.chunks[3].type, ChunkType.RCode)
		XCTAssertEqual(parser.chunks[4].type, ChunkType.Documentation)
		XCTAssertEqual(parser.chunks[5].type, ChunkType.Equation)
		XCTAssertEqual(parser.chunks[4].type, ChunkType.Documentation)
		
		//TODO: check equation chunks have correct range and background color
	}
}
