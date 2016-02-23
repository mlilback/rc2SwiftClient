//
//  ImageCacheTests.swift
//  SwiftClient
//
//  Created by Mark Lilback on 1/27/16.
//  Copyright © 2016 Rc2. All rights reserved.
//

import XCTest
@testable import MacClient

class ImageCacheTests: BaseTest {

	func testExistingImageForId() {
		let cache = ImageCache(mockFM)
		cache.workspace = sessionData.workspaces.first
		let srcImage : NSURL = NSBundle(forClass: ImageCacheTests.self).URLForResource("graph", withExtension: "png")!
		let destUrl = NSURL(string: "1.png", relativeToURL: cache.cacheUrl)!
		if destUrl.checkPromisedItemIsReachableAndReturnError(nil) {
			try! mockFM.removeItemAtURL(destUrl)
		}
		try! mockFM.copyItemAtURL(srcImage, toURL: destUrl)
		cache.imageWithId(1).onSuccess { image in
			XCTAssert(self.mockFM.contentsEqualAtPath(srcImage.absoluteURL.path!, andPath: destUrl.absoluteURL.path!))
		}.onFailure { error in
			XCTFail("test failed: \(error)")
		}
	}

}
