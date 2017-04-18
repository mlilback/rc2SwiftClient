//
//  DockerImageTest.swift
//  SwiftClient
//
//  Created by Mark Lilback on 9/2/16.
//  Copyright © 2016 Rc2. All rights reserved.
//

import XCTest
import Freddy
@testable import Docker

class DockerImageTest: XCTestCase {
	var jsonArray:JSON?

	override func setUp() {
		super.setUp()
		let path : String = Bundle(for: DockerImageTest.self).path(forResource: "dockerImages", ofType: "json")!
		let resultData = try! Data(contentsOf: URL(fileURLWithPath: path))
		jsonArray = try! JSON(data:resultData)
	}
	
	override func tearDown() {
		// Put teardown code here. This method is called after the invocation of each test method in the class.
		super.tearDown()
	}

	func testReadImages() {
		var images:[DockerImage] = try! jsonArray!.decodedArray(at: "images")
		XCTAssertEqual(images.count, 1)
		XCTAssertEqual(images[0].tags.count, 1)
		XCTAssertEqual(images[0].tags.first?.name, "dbserver")
	}
}
