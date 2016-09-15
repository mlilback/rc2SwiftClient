//
//  DockerImageTest.swift
//  SwiftClient
//
//  Created by Mark Lilback on 9/2/16.
//  Copyright © 2016 Rc2. All rights reserved.
//

import XCTest
import SwiftyJSON
@testable import ClientCore

class DockerImageTest: XCTestCase {
	var jsonArray:JSON?

	override func setUp() {
		super.setUp()
		let path : String = Bundle(for: DockerImageTest.self).path(forResource: "dockerImages", ofType: "json")!
		let resultData = try! Data(contentsOf: URL(fileURLWithPath: path))
		jsonArray = JSON(data:resultData)
	}
	
	override func tearDown() {
		// Put teardown code here. This method is called after the invocation of each test method in the class.
		super.tearDown()
	}

	func testReadImages() {
		var images:[DockerImage] = []
		for anImageJson in jsonArray!.arrayValue {
			images.append(DockerImage(json: anImageJson)!)
		}
		XCTAssertEqual(images.count, 1)
		XCTAssertEqual(images[0].tags.count, 1)
		XCTAssertEqual(images[0].tags.first?.name, "dbserver")
	}
	
	func testImageSerialization() {
		let original:[DockerImage] = (jsonArray?.arrayValue.map() { return DockerImage(json: $0)! })!
		let json = JSON(original.map() { try! $0.serialize() })
		var images:[DockerImage] = []
		for anImageJson in json.arrayValue {
			images.append(DockerImage(json: anImageJson)!)
		}
		XCTAssertEqual(original.count, images.count)
		for (idx, obj) in images.enumerated() {
			XCTAssertEqual(obj, original[idx])
		}
	}
}
