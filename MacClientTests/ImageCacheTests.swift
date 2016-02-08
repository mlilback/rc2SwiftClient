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
		let srcImage : NSURL = NSBundle(forClass: ImageCacheTests.self).URLForResource("graph", withExtension: "png")!
		let destUrl = NSURL(string: "1.png", relativeToURL: mockFM.tempDirUrl)!
		if destUrl.checkPromisedItemIsReachableAndReturnError(nil) {
			try! mockFM.removeItemAtURL(destUrl)
		}
		try! mockFM.copyItemAtURL(srcImage, toURL: destUrl)
		let cache = ImageCache(mockFM)
		cache.workspace = sessionData.workspaces.first
		cache.imageWithId(1).onSuccess { image in
			XCTAssertEqual(image, NSImage(contentsOfURL: srcImage))
		}.onFailure { error in
			XCTFail("test failed: \(error)")
		}
	}

}
