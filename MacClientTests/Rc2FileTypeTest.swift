//
//  Rc2FileTypeTest.swift
//  SwiftClient
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import XCTest
@testable import MacClient

class Rc2FileTypeTest: XCTestCase {

	override func setUp() {
		super.setUp()
		// Put setup code here. This method is called before the invocation of each test method in the class.
	}
	
	override func tearDown() {
		// Put teardown code here. This method is called after the invocation of each test method in the class.
		super.tearDown()
	}

	func testFileTypes() {
		XCTAssert(FileType.allFileTypes.count > 12, "too few file types")
		let  sweave = FileType.fileTypeWithExtension("Rnw")!
		XCTAssertTrue(sweave.isSweave)
		XCTAssertFalse(sweave.isImage)
		let  png = FileType.fileTypeWithExtension("png")!
		XCTAssertTrue(png.isImage)
		XCTAssertFalse(png.isSourceFile)
		XCTAssertEqual(png.mimeType, "image/png")
		XCTAssertEqual(FileType.imageFileTypes.count, 3)
		XCTAssertTrue(FileType.imageFileTypes.contains(png))
	}
}
