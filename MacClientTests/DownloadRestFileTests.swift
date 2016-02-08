//
//  DownloadRestFileTests.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import XCTest
@testable import MacClient
import Mockingjay

class DownloadRestFileTests: XCTestCase {
	var cacheDir: NSURL!
	let server: RestServer = RestServer()
	
	override class func initialize() {
		NSURLSessionConfiguration.mockingjaySwizzleDefaultSessionConfiguration()
	}
	
	class CacheFileManager: DefaultFileManager {
		let cacheDir: NSURL!
		init(_ cacheDir:NSURL) {
			self.cacheDir = cacheDir
			super.init()
		}
		override func URLForDirectory(directory: NSSearchPathDirectory, inDomain domain: NSSearchPathDomainMask, appropriateForURL url: NSURL?, create shouldCreate: Bool) throws -> NSURL
		{
			if directory == .CachesDirectory {
				return cacheDir
			}
			return try super.URLForDirectory(directory, inDomain: domain, appropriateForURL: url, create: shouldCreate)
		}
	}
	
	override func setUp() {
		super.setUp()
		let tmpDir = NSURL(fileURLWithPath: NSTemporaryDirectory())
		cacheDir = NSURL(fileURLWithPath: "rc2CacheTest", isDirectory: true, relativeToURL: tmpDir).absoluteURL
		try! NSFileManager.defaultManager().createDirectoryAtURL(cacheDir, withIntermediateDirectories: true, attributes: nil)
		Workspace.fileManager = CacheFileManager(self.cacheDir)
	}

	override func tearDown() {
		Workspace.fileManager = NSFileManager.defaultManager()
		try! NSFileManager.defaultManager().removeItemAtURL(cacheDir)
		super.tearDown()
	}
	
	func testDownloadFile() {
		let wspace = workspace1()
		let fpath = NSBundle(forClass: self.dynamicType).pathForResource("graph", ofType: "png")!
		let fdata = NSData(contentsOfFile: fpath)!
		let destUri = "/workspaces/\(wspace.wspaceId)/files/\(wspace.files[0].fileId)"
		stub(uri(destUri), builder: http(200, headers:["Content-Type":"img/png"], data:fdata))
		let expect = self.expectationWithDescription("file download")
		server.downloadFile(wspace, file: wspace.files[0]).onSuccess { (url) -> Void in
			XCTAssertEqual(NSData(contentsOfURL: url!), fdata)
			expect.fulfill()
		}.onFailure { (error) -> Void in
			XCTAssert(false)
			expect.fulfill()
		}
		self.waitForExpectationsWithTimeout(2) { (err) -> Void in }
	}
	
	func workspace1() -> Workspace {
		let path : String = NSBundle(forClass: RestServerTest.self).pathForResource("loginResults", ofType: "json")!
		let resultData = NSData(contentsOfFile: path)
		let loginJson = JSON.parse(String(data: resultData!, encoding: NSUTF8StringEncoding)!)
		return Workspace(json:loginJson["workspaces"].arrayValue[0])
	}
}
