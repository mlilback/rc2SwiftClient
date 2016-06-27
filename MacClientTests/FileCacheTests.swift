//
//  FileCacheTests.swift
//  SwiftClient
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import XCTest
@testable import MacClient
import BrightFutures
import Mockingjay
import SwiftyJSON

class FileCacheTests: BaseTest {
	var cache:FileCache!
	var wspace:Workspace!
	var file:File!
	var filePath:String!
	var fileData:NSData!
	var destUri:String!
	var cachedUrl:NSURL!
	var baseUrl:NSURL = NSURL(string: "http://localhost/")!
	var multiExpectation:XCTestExpectation?

	override class func initialize() {
		NSURLSessionConfiguration.mockingjaySwizzleDefaultSessionConfiguration()
	}
	
	override func setUp() {
		super.setUp()
		wspace = sessionData.projects.first!.workspaces.first!
		cache = FileCache(workspace: wspace, baseUrl: baseUrl, config: NSURLSessionConfiguration.defaultSessionConfiguration())
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
	
	//TODO: needs to actually test the second file was downloaded correctly
	func testMultipleDownload() {
		//use contents of words file instead of the R file we use in other tests (i.e. make it a lot larger)
		let wordsUrl = NSURL(fileURLWithPath: "/usr/share/dict/words")
		fileData = NSData(contentsOfURL: wordsUrl)!
		let fakeFile = File(json: JSON.parse("{\"id\" : 1,\"wspaceId\" : 1,\"name\" : \"sample.R\",\"version\" : 0,\"dateCreated\" : 1439407405827,\"lastModified\" : 1439407405827,\"etag\": \"f/1/0\", \"fileSize\":\(fileData.length) }"))
		file = fakeFile
		wspace.replaceFile(at:0, withFile: fakeFile)
		//stub out download of both files
		stub(uri("/workspaces/\(wspace.wspaceId)/files/\(wspace.files[0].fileId)"), builder: http(200, headers:[:], data:fileData))
		let file1Data = fileData.subdataWithRange(NSMakeRange(0, wspace.files[1].fileSize))
		stub(uri("/workspaces/\(wspace.wspaceId)/files/\(wspace.files[1].fileId)"), builder: http(200, headers:[:], data:file1Data))
		
		multiExpectation = expectationWithDescription("download from server")
		cache.cacheAllFiles() { (prog) in
			prog.rc2_addCompletionHandler() {
				self.multiExpectation?.fulfill()
			}
		}
		self.waitForExpectationsWithTimeout(60) { (err) -> Void in }
		var fileSize:UInt64 = 0
		do {
			let fileAttrs:NSDictionary = try NSFileManager.defaultManager().attributesOfItemAtPath(cachedUrl.path!)
			fileSize = fileAttrs.fileSize()
		} catch let e as NSError {
			XCTAssertFalse(true, "error getting file size:\(e)")
		}
		XCTAssertEqual(fileSize, UInt64(fileData.length))
	}
	
}
