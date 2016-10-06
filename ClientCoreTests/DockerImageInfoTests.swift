//
//  DockerImageInfoTests.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import XCTest
@testable import ClientCore
import Mockingjay
import SwiftyJSON

class DockerImageInfoTests: XCTestCase {
	var sessionConfig:URLSessionConfiguration!
	
	override func setUp() {
		super.setUp()
		sessionConfig = URLSessionConfiguration.default
		sessionConfig.protocolClasses = [MockingjayProtocol.self, DockerUrlProtocol.self] as [AnyClass] + sessionConfig.protocolClasses!
	}

	func testParseInfo() {
		let path : String = Bundle(for: DockerImageInfoTests.self).path(forResource: "imageInfo", ofType: "json")!
		let resultData = try? Data(contentsOf: URL(fileURLWithPath: path))
		stub(http(method: .get, uri: "/imageInfo.json"), builder: jsonData(resultData!))
		var fetchedData: Data?
		let expect = expectation(description: "fetch imageinfo")
		var error: NSError?
		let session = URLSession(configuration: URLSessionConfiguration.default)
		let task = session.dataTask(with: URL(string: "http://www.rc2.io/imageInfo.json")!) { data, rsp, err in
			error = err as NSError?
			fetchedData = data
			expect.fulfill()
		}
		task.resume()
		waitForExpectations(timeout: 2) { _ in
			XCTAssertNil(error)
			let json = JSON(data: fetchedData!)
			let info = RequiredImageInfo(json:json)!
			XCTAssertEqual(info.version, 1)
			XCTAssertEqual(info.dbserver.size, 442069860)
			XCTAssertEqual(info.computeserver.name, "compute")
		}
	}
}
