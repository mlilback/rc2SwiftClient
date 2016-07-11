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
		let cache = ImageCache(restServer:RestServer(host:serverHost), fileManager:mockFM, hostIdentifier: "blah")
		cache.workspace = sessionData.projects.first!.workspaces.first
		let srcImage : NSURL = NSBundle(forClass: ImageCacheTests.self).URLForResource("graph", withExtension: "png")!
		let destUrl = NSURL(string: "1.png", relativeToURL: cache.cacheUrl)!
		if destUrl.checkPromisedItemIsReachableAndReturnError(nil) {
			try! mockFM.removeItemAtURL(destUrl)
		}
		let expect = expectationWithDescription("fetch image from cache")
		try! mockFM.copyItemAtURL(srcImage, toURL: destUrl)
		cache.imageWithId(1).onSuccess { image in
			XCTAssert(self.mockFM.contentsEqualAtPath(srcImage.absoluteURL!.path!, andPath: destUrl.absoluteURL!.path!))
			expect.fulfill()
		}.onFailure { error in
			XCTFail("test failed: \(error)")
			expect.fulfill()
		}
		self.waitForExpectationsWithTimeout(2) { (err) -> Void in }
	}

}
