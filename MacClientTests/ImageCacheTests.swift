//
//  ImageCacheTests.swift
//  SwiftClient
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import XCTest
@testable import MacClient

class ImageCacheTests: BaseTest {

	func testExistingImageForId() {
		let cache = ImageCache(restServer:RestServer(host:serverHost), fileManager:FileManager.default, hostIdentifier: "blah")
		cache.workspace = sessionData.projects.first!.workspaces.first
		let srcImage : URL = Bundle(for: ImageCacheTests.self).url(forResource: "graph", withExtension: "png")!
		let destUrl = URL(string: "1.png", relativeTo: cache.cacheUrl)!
		if try! destUrl.checkPromisedItemIsReachable() {
			try! mockFM.removeItem(at:destUrl)
		}
		let expect = expectation(description: "fetch image from cache")
		try! mockFM.copyItem(at:srcImage, to: destUrl)
		cache.imageWithId(1).onSuccess { image in
			XCTAssert(self.mockFM.contentsEqual(atPath: srcImage.absoluteURL.path, andPath: destUrl.absoluteURL.path))
			expect.fulfill()
		}.onFailure { error in
			XCTFail("test failed: \(error)")
			expect.fulfill()
		}
		self.waitForExpectations(timeout: 2) { (err) -> Void in }
	}

}
