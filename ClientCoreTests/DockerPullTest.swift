//
//  DockerPullTest.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import XCTest
@testable import ClientCore

class DockerPullTest: XCTestCase {
	var expect:XCTestExpectation?
	var unitCount: Int64 = 0
	var savedError: NSError?

	override func setUp() {
		expect = expectation(description: "busybox pull")
	}
	
	func testBusyBoxPull() {
		let rawData = try! Data(contentsOf: Bundle(for: DockerPullTest.self).url(forResource: "busybox", withExtension: "jsonData")!)
		let completeStr = String(data: rawData, encoding: .ascii)!
		let lines = completeStr.components(separatedBy: "\n")
		let data = lines.map() { return ($0 + "\r\n").data(using: .utf8)! }
		TestDataProtocol.responseData = data
		TestDataProtocol.responseHeaders = ["Content-Type":"application/json", "Content-size": String(completeStr.characters.count)]

		let config = URLSessionConfiguration.default
		config.protocolClasses = [TestDataProtocol.self, DockerUrlProtocol.self] as [AnyClass] + config.protocolClasses!
		let url = URL(string: "test://foo.com/bar")!
		let pullOp = DockerPullOperation(baseUrl: url, imageName: "busybox", estimatedSize: 667590, config: config)
		let future = pullOp.startPull() { progress in
			self.unitCount = progress.currentSize
		}
		future.onSuccess { _ in
			self.unitCount = pullOp.pullProgress.currentSize
			self.expect!.fulfill()
		}.onFailure { err in
			self.savedError = err
			self.expect!.fulfill()
		}
		waitForExpectations(timeout: 2) { err in
			XCTAssertNil(self.savedError)
			XCTAssertEqual(self.unitCount, 667590)
		}
	}
}

