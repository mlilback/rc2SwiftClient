//
//  SyntaxParserTests
//  Rc2Client
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import XCTest
@testable import SyntaxParsing
import Networking
import Model

class SyntaxParsingTests: XCTestCase {
	var storage: NSTextStorage!
	var parser: BaseSyntaxParser!
	
	override func setUp() {
		super.setUp()
		storage = NSTextStorage()
	}
	
	override func tearDown() {
		super.tearDown()
	}
	
	func loadStorageWith(_ filename: String, suffix: String) {
		parser = BaseSyntaxParser.parserWithTextStorage(storage, fileType: FileType.fileType(withExtension: suffix)!) { _ in return false }
		let fileUrl = Bundle(for: type(of: self)).url(forResource: filename, withExtension: suffix, subdirectory: nil)!
		let contents = try! String(contentsOf: fileUrl, encoding: String.Encoding.utf8)
		storage.replaceCharacters(in: NSMakeRange(0, storage.string.utf8.count), with: contents)
	}
	
	func testChunkBreaks() {
		//storage must be non-empty and not the same length as the range
		// we are testing. "foo" should do
		storage.append(NSAttributedString(string: "foo"))
		let chunks = [
			DocumentChunk(chunkType: .equation, chunkNumber: 1),
			DocumentChunk(chunkType: .documentation, chunkNumber: 2),
			DocumentChunk(chunkType: .executable, chunkNumber: 3)
		]
		chunks[0].parsedRange = NSMakeRange(0, 10)
		chunks[1].parsedRange = NSMakeRange(10, 20)
		chunks[2].parsedRange = NSMakeRange(30, 30)
		parser = BaseSyntaxParser.parserWithTextStorage(storage, fileType: FileType.fileType(withExtension: "Rmd")!) { _ in return false }
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
		_ = parser.parse()
		XCTAssertEqual(parser.chunks.count, 5)
		XCTAssertEqual(parser.chunks[0].type, ChunkType.documentation)
		XCTAssertEqual(parser.chunks[1].type, ChunkType.executable)
		XCTAssertEqual(parser.chunks[2].type, ChunkType.documentation)
		XCTAssertEqual(parser.chunks[3].type, ChunkType.executable)
		XCTAssertEqual(parser.chunks[3].name, "fig=TRUE,echo=FALSE")
		XCTAssertEqual(parser.chunks[4].type, ChunkType.documentation)
	}
	
	func testMarkdown1() {
		loadStorageWith("syntax2", suffix:"Rmd")
		_ = parser.parse()
		XCTAssertEqual(parser.chunks.count, 7)
		XCTAssertEqual(parser.chunks[0].type, ChunkType.documentation)
		XCTAssertEqual(parser.chunks[1].type, ChunkType.equation)
		XCTAssertEqual(parser.chunks[2].type, ChunkType.documentation)
		XCTAssertEqual(parser.chunks[3].type, ChunkType.executable)
		XCTAssertEqual(parser.chunks[4].type, ChunkType.documentation)
		XCTAssertEqual(parser.chunks[5].type, ChunkType.equation)
		XCTAssertEqual(parser.chunks[4].type, ChunkType.documentation)
		
		//TODO: check equation chunks have correct range and background color
	}
}

