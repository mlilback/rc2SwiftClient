//
//  ImageCacheTests.swift
//  SwiftClient
//
//  Created by Mark Lilback on 1/27/16.
//  Copyright © 2016 Rc2. All rights reserved.
//

import XCTest
@testable import MacClient

class ImageCacheTests: XCTestCase {

	func testExistingImageForId() {
		let srcImage : NSURL = NSBundle(forClass: ImageCacheTests.self).URLForResource("graph", withExtension: "png")!
		let fm = MockFileManager()
		fm.dirUrl = NSURL(fileURLWithPath: NSTemporaryDirectory().stringByAppendingFormat("/%@", NSUUID().UUIDString))
		try! fm.createDirectoryAtURL(fm.dirUrl!, withIntermediateDirectories: true, attributes: nil)
		let destUrl = NSURL(string: "1.png", relativeToURL: fm.dirUrl)!
		if destUrl.checkPromisedItemIsReachableAndReturnError(nil) {
			try! fm.removeItemAtURL(destUrl)
		}
		defer {
			try! fm.removeItemAtURL(fm.dirUrl!)
		}
		try! fm.copyItemAtURL(srcImage, toURL: destUrl)
		let cache = ImageCache(fm)
		cache.imageWithId(1).onSuccess { image in
			XCTAssertEqual(image, NSImage(contentsOfURL: srcImage))
		}.onFailure { error in
			XCTFail("test failed: \(error)")
		}
	}

	class MockFileManager: NSFileManager {
		var dirUrl: NSURL?
		
		override func URLForDirectory(directory: NSSearchPathDirectory, inDomain domain: NSSearchPathDomainMask, appropriateForURL url: NSURL?, create shouldCreate: Bool) throws -> NSURL
		{
			return dirUrl!
		}
	}
}
