//
//  FileCacheTests.swift
//  SwiftClient
//
//  Created by Mark Lilback on 2/8/16.
//  Copyright © 2016 Rc2. All rights reserved.
//

import XCTest
@testable import MacClient
import BrightFutures
import Mockingjay

class FileCacheTests: BaseTest, FileCacheDownloadDelegate {
	var cache:FileCache!
	var wspace:Workspace!
	var file:File!
	var filePath:String!
	var fileData:NSData!
	var destUri:String!
	var cachedUrl:NSURL!
	var multiExpectation:XCTestExpectation?

	override class func initialize() {
		NSURLSessionConfiguration.mockingjaySwizzleDefaultSessionConfiguration()
	}
	
	override func setUp() {
		super.setUp()
		cache = FileCache()
		wspace = sessionData.workspaces.first!
		file = (wspace.files.first)!
		filePath = NSBundle(forClass: self.dynamicType).pathForResource("lognormal", ofType: "R")!
		fileData = NSData(contentsOfFile: filePath)!
		destUri = "/workspaces/\(wspace.wspaceId)/files/\(wspace.files[0].fileId)"
		cachedUrl = cache.cachedFileUrl(file)
		do { try mockFM.removeItemAtURL(cachedUrl) } catch _ {}
	}
	
	override func tearDown() {
		do { try mockFM.removeItemAtURL(cachedUrl) } catch _ {}
		super.tearDown()
	}
	
	func testDownload() {
		XCTAssertFalse(cache.isFileCached(file))
		//test download
		stub(uri(destUri), builder: http(200, headers:["Content-Type":file.fileType.mimeType], data:fileData))
		let expect = expectationWithDescription("download from server")
		cache.downloadFile(file, fromWorkspace: wspace).onSuccess { (furl) -> Void in
			XCTAssertEqual(NSData(contentsOfURL: furl!), self.fileData, "data failed to match")
			XCTAssert(self.file.urlXAttributesMatch(furl!), "xattrs don't match")
			expect.fulfill()
		}.onFailure { (error) -> Void in
			XCTAssert(false)
			expect.fulfill()
		}
		self.waitForExpectationsWithTimeout(2) { (err) -> Void in }
	}
	
	func testCacheHit() {
		fileData.writeToURL(cachedUrl, atomically: true)
		file.writeXAttributes(cachedUrl)
		
		//test file is cached
		stub(uri(destUri), builder: http(404, headers:[:], data:fileData))
		let expect = expectationWithDescription("download from server")
		cache.downloadFile(file, fromWorkspace: wspace).onSuccess { (furl) -> Void in
			XCTAssertEqual(NSData(contentsOfURL: furl!), self.fileData)
			XCTAssert(self.file.urlXAttributesMatch(furl!))
			expect.fulfill()
		}.onFailure { (error) -> Void in
			XCTAssert(false)
			expect.fulfill()
		}
		self.waitForExpectationsWithTimeout(2) { (err) -> Void in }
	}

	func testNoSuchFile() {
		stub(uri(destUri), builder: http(404, headers:[:], data:fileData))
		let expect = expectationWithDescription("404 from server")
		cache.downloadFile(file, fromWorkspace: wspace).onSuccess { (furl) -> Void in
			XCTFail("404 download was a success")
			expect.fulfill()
			}.onFailure { (error) -> Void in
				XCTAssertTrue(error == .FileNotFound)
				expect.fulfill()
		}
		self.waitForExpectationsWithTimeout(2) { (err) -> Void in }
	}

	func testMultipleDownload() {
		stub(everything, builder: http(200, headers:[:], data:fileData))
		multiExpectation = expectationWithDescription("download from server")
		try! cache.cacheFilesForWorkspace(wspace, delegate:self)
		self.waitForExpectationsWithTimeout(120) { (err) -> Void in }
	}
	
	///called as bytes are recieved over the network
	func fileCache(cache:FileCache, updatedProgressWithStatus progress:FileCacheDownloadStatus) {
		//TODO: inspect that the percentage is what we expect
		log.info("got progress")
	}
	
	///called when all the files have been downloaded and cached
	func fileCacheDidFinishDownload(cache:FileCache, workspace:Workspace) {
		log.info("got complete")
		multiExpectation?.fulfill()
	}
	
	///called on error. The download is canceled and fileCacheDidFinishDownload is not called
	func fileCache(cache:FileCache, failedToDownload file:File, error:ErrorType) {
		log.info("error for dload:\(error)")
		multiExpectation?.fulfill()
	}

}
