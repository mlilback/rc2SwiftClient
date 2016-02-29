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
	
	func testSweave1() {
		loadStorageWith("syntax1", suffix:"Rnw")
		parser.parse()
		XCTAssertEqual(parser.chunks.count, 5)
		XCTAssertEqual(parser.chunks[0].type, ChunkType.Documentation)
		XCTAssertEqual(parser.chunks[1].type, ChunkType.RCode)
		XCTAssertEqual(parser.chunks[2].type, ChunkType.Documentation)
		XCTAssertEqual(parser.chunks[3].type, ChunkType.RCode)
		XCTAssertEqual(parser.chunks[4].type, ChunkType.Documentation)
	}
	
	func testMarkdown1() {
		loadStorageWith("syntax2", suffix:"Rmd")
		parser.parse()
		XCTAssertEqual(parser.chunks.count, 3)
//		XCTAssertEqual(parser.chunks[0].type, ChunkType.Documentation)
//		XCTAssertEqual(parser.chunks[1].type, ChunkType.RCode)
//		XCTAssertEqual(parser.chunks[2].type, ChunkType.Documentation)
//		XCTAssertEqual(parser.chunks[3].type, ChunkType.RCode)
//		XCTAssertEqual(parser.chunks[4].type, ChunkType.Documentation)
	}
}
