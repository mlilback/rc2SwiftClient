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
		storage.replaceCharacters(in: NSMakeRange(0, storage.string.count), with: contents)
	}
	
	func testCodeTagsToIgnore() {
		parser = BaseSyntaxParser.parserWithTextStorage(storage, fileType: FileType.fileType(withExtension: "Rmd")!) { _ in return false }
		let str = "#comment: $n$ `r x=1`\n<!--\n$$a$$-->``"
		storage.append(NSAttributedString(string: str))
		for c in parser.chunks {
			print("num=\(c.chunkNumber)\t range=\(c.parsedRange)\t type=\(c.chunkType),\(c.equationType)")
		}
		XCTAssertTrue(parser.parse())
		XCTAssertEqual(parser.chunks[0].chunkType, ChunkType.docs)
		XCTAssertEqual(parser.chunks[0].parsedRange.length, str.count)
		parser.colorChunks(parser.chunks)
	}

	func testRmdFile1() {
		loadStorageWith("syntax2", suffix:"Rmd")
		_ = parser.parse()
		for c in parser.chunks {
			print("num=\(c.chunkNumber)\t range=\(c.parsedRange)\t type=\(c.chunkType),\(c.equationType)")
		}
		XCTAssertEqual(parser.chunks.count, 9)
		XCTAssertEqual(parser.chunks[0].chunkType, ChunkType.docs)
		XCTAssertEqual(parser.chunks[0].docType, DocType.rmd)
		XCTAssertEqual(parser.chunks[1].chunkType, ChunkType.equation)
		XCTAssertEqual(parser.chunks[1].equationType, EquationType.display)
		XCTAssertEqual(parser.chunks[2].chunkType, ChunkType.docs)
		XCTAssertEqual(parser.chunks[3].chunkType, ChunkType.code)
		XCTAssertEqual(parser.chunks[4].chunkType, ChunkType.equation)
		XCTAssertEqual(parser.chunks[4].equationType, EquationType.inline)
		XCTAssertEqual(parser.chunks[5].chunkType, ChunkType.docs)
		XCTAssertEqual(parser.chunks[6].chunkType, ChunkType.code)
		XCTAssertEqual(parser.chunks[7].chunkType, ChunkType.docs)
		XCTAssertEqual(parser.chunks[8].chunkType, ChunkType.equation)
		XCTAssertEqual(parser.chunks[8].equationType, EquationType.mathML)
		XCTAssertEqual(parser.chunks[8].parsedRange.location, 329)
		XCTAssertEqual(parser.chunks[8].parsedRange.length, 193)
	}
	
	func testSweave1() {
		loadStorageWith("syntax1", suffix:"Rnw")
		_ = parser.parse()
		for c in parser.chunks {
			print("num=\(c.chunkNumber)\t range=\(c.parsedRange)\t type=\(c.chunkType),\(c.equationType)")
		}
		XCTAssertEqual(parser.chunks.count, 9)
		XCTAssertEqual(parser.chunks[0].chunkType, ChunkType.docs)
		XCTAssertEqual(parser.chunks[0].docType, DocType.latex)
		XCTAssertEqual(parser.chunks[1].chunkType, ChunkType.equation)
		XCTAssertEqual(parser.chunks[1].equationType, EquationType.display)
		XCTAssertEqual(parser.chunks[2].chunkType, ChunkType.docs)
		XCTAssertEqual(parser.chunks[3].chunkType, ChunkType.equation)
		XCTAssertEqual(parser.chunks[3].equationType, EquationType.inline)
		XCTAssertEqual(parser.chunks[4].chunkType, ChunkType.docs)
		XCTAssertEqual(parser.chunks[5].chunkType, ChunkType.code)
		XCTAssertEqual(parser.chunks[6].chunkType, ChunkType.docs)
		XCTAssertEqual(parser.chunks[7].chunkType, ChunkType.code)
		XCTAssertEqual(parser.chunks[8].chunkType, ChunkType.docs)
		XCTAssertEqual(parser.chunks[8].parsedRange.location, 781)
		XCTAssertEqual(parser.chunks[8].parsedRange.length, 29)
	}
	
//	func testChunkBreaks() {
		//		storage.append(NSAttributedString(string: "foo"))
		//		let chunks = [
		//			DocumentChunk(chunkType: .equation, chunkNumber: 1),
		//			DocumentChunk(chunkType: .documentation, chunkNumber: 2),
		//			DocumentChunk(chunkType: .executable, chunkNumber: 3)
		//		]
		//		chunks[0].parsedRange = NSMakeRange(0, 10)
		//		chunks[1].parsedRange = NSMakeRange(10, 20)
		//		chunks[2].parsedRange = NSMakeRange(30, 30)
		//		parser = BaseSyntaxParser.parserWithTextStorage(storage, fileType: FileType.fileType(withExtension: "Rmd")!) { _ in return false }
		//		parser.chunks = chunks
		//		//test empty range which should return first chunk
		//		var results = parser.chunksForRange(NSMakeRange(0, 0))
		//		XCTAssertEqual(results.count, 1)
		//		XCTAssertEqual(results[0], chunks[0])
		//		//test with one matching chunk
		//		results = parser.chunksForRange(NSMakeRange(1, 1))
		//		XCTAssertEqual(results.count, 1)
		//		XCTAssertEqual(results[0], chunks[0])
		//		//test with 2 matching chunks
		//		results = parser.chunksForRange(NSMakeRange(9, 4))
		//		XCTAssertEqual(results.count, 2)
		//		XCTAssertEqual(results[0], chunks[0])
		//		XCTAssertEqual(results[1], chunks[1])
		//		//test empty range at end of first chunk (i.e. deleting at border)
		//		results = parser.chunksForRange(NSMakeRange(10, 0))
		//		XCTAssertEqual(results.count, 1)
		////		XCTAssertEqual(results[0], chunks[0])
		//		//test inserting at start of second chunk
		//		results = parser.chunksForRange(NSMakeRange(10, 1))
		//		XCTAssertEqual(results.count, 1)
		//		XCTAssertEqual(results[0], chunks[1])
		//
//	}
	
}

