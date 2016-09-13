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
	var fileData:Data!
	var destUri:String!
	var cachedUrl:URL!
	var baseUrl:URL = URL(string: "http://localhost/")!
	var multiExpectation:XCTestExpectation?

	override class func initialize() {
		URLSessionConfiguration.mockingjaySwizzleDefaultSessionConfiguration()
	}
	
	override func setUp() {
		super.setUp()
		wspace = sessionData.projects.first!.workspaces.first!
		cache = FileCache(workspace: wspace, baseUrl: baseUrl, config: URLSessionConfiguration.default, appStatus:nil)
		file = (wspace.files.first)!
		filePath = Bundle(for: type(of: self)).path(forResource: "lognormal", ofType: "R")!
		fileData = try! Data(contentsOf: URL(fileURLWithPath: filePath))
		destUri = "/workspaces/\(wspace.wspaceId)/files/\(wspace.files[0].fileId)"
		cachedUrl = cache.cachedFileUrl(file)
		do { try mockFM.removeItem(at: cachedUrl) } catch _ {}
	}
	
	override func tearDown() {
		do { try mockFM.removeItem(at: cachedUrl) } catch _ {}
		super.tearDown()
	}
	
	//TODO: needs to actually test the second file was downloaded correctly
	func testMultipleDownload() {
		//use contents of words file instead of the R file we use in other tests (i.e. make it a lot larger)
		let wordsUrl = URL(fileURLWithPath: "/usr/share/dict/web2")
		fileData = try! Data(contentsOf: wordsUrl)
		let fakeFile = File(json: JSON.parse("{\"id\" : 1,\"wspaceId\" : 1,\"name\" : \"sample.R\",\"version\" : 0,\"dateCreated\" : 1439407405827,\"lastModified\" : 1439407405827,\"etag\": \"f/1/0\", \"fileSize\":\(fileData.count) }"))
		file = fakeFile
		wspace.replaceFile(at:0, withFile: fakeFile)
		//stub out download of both files
		stub(uri(uri: "/workspaces/\(wspace.wspaceId)/files/\(wspace.files[0].fileId)"), builder: http(200, headers:[:], download:Download.content(fileData)))
		let file1Data = fileData.subdata(in: 0..<wspace.files[1].fileSize)
		stub(uri(uri: "/workspaces/\(wspace.wspaceId)/files/\(wspace.files[1].fileId)"), builder: http(200, headers:[:], download:Download.content(file1Data)))
		
		multiExpectation = expectation(description: "download from server")
		cache.cacheAllFiles() { (prog) in
			prog.rc2_addCompletionHandler() {
				self.multiExpectation?.fulfill()
			}
		}
		self.waitForExpectations(timeout: 60) { (err) -> Void in }
		var fileSize:UInt64 = 0
		do {
			let fileAttrs = try FileManager.default.attributesOfItem(atPath: wordsUrl.path)
			fileSize = (fileAttrs[FileAttributeKey.size] as! NSNumber).uint64Value
		} catch let e as NSError {
			XCTAssertFalse(true, "error getting file size:\(e)")
		}
		XCTAssertEqual(fileSize, UInt64(fileData.count))
	}
	
}
