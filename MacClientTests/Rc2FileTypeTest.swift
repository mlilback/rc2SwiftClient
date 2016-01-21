//
//  Rc2FileTypeTest.swift
//  Rc2Client
//
//  Created by Mark Lilback on 12/18/15.
//  Copyright © 2015 West Virginia University. All rights reserved.
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
