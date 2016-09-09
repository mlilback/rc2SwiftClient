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
@testable import MacClient

class DockerImageTest: XCTestCase {
	var jsonArray:JSON?

	override func setUp() {
		super.setUp()
		let path : String = NSBundle(forClass: DockerImageTest.self).pathForResource("dockerImages", ofType: "json")!
		let resultData = NSData(contentsOfFile: path)
		jsonArray = JSON(data:resultData!)
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
		let json = JSON(original.map() { try! $0.toJson() })
		var images:[DockerImage] = []
		for anImageJson in json.arrayValue {
			images.append(DockerImage(json: anImageJson)!)
		}
		XCTAssertEqual(original.count, images.count)
		for (idx, obj) in images.enumerate() {
			XCTAssertEqual(obj, original[idx])
		}
	}
}
