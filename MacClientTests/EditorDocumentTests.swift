//
//  EditorDocumentTests.swift
//  SwiftClient
//
//  Created by Mark Lilback on 3/2/16.
//  Copyright © 2016 Rc2. All rights reserved.
//

import XCTest
@testable import MacClient

class EditorDocumentTests: BaseTest {
	var fileHandler:DefaultSessionFileHandler?
	var appStatus:MockAppStatus = MockAppStatus()
	var startFileContents:String = "file contents go here\n"
	var file:File!
	var fileUrl:NSURL!
	
	override func setUp() {
		super.setUp()
		let wspace = sessionData!.projects.first!.workspaces[0]
		file = wspace.files[0]
		let cacheDir = mockFM.tempDirUrl.URLByAppendingPathComponent("io.rc2.MacClient", isDirectory: true).URLByAppendingPathComponent("FileCache", isDirectory: true).absoluteURL
		try! mockFM.createDirectoryAtURL(cacheDir, withIntermediateDirectories: true, attributes: nil)
		fileUrl = NSURL(fileURLWithPath: "\(file!.fileId).R", relativeToURL: cacheDir).absoluteURL
		try! startFileContents.writeToURL(fileUrl, atomically: true, encoding: NSUTF8StringEncoding)
		fileHandler = DefaultSessionFileHandler(wspace: wspace, baseUrl: mockFM.tempDirUrl, config: NSURLSessionConfiguration.defaultSessionConfiguration(), appStatus: appStatus)
		fileHandler?.fileCache.fileManager = mockFM
		
	}
	
	override func tearDown() {
		super.tearDown()
	}

	func testSave() {
		XCTAssertEqual(appStatus.setCount, 0)
		let doc = EditorDocument(file: file, fileHandler: fileHandler!)
		XCTAssertEqual(startFileContents, doc.savedContents)
		let modContent = "foo  bar \n baz"
		doc.willBecomeInactive(modContent)
		XCTAssertEqual(doc.currentContents, modContent)
		let expect = expectationWithDescription("save file")
		let prog = doc.saveContents()
		prog?.rc2_addCompletionHandler() {
			expect.fulfill()
		}
		self.waitForExpectationsWithTimeout(2){ (error) in }
		XCTAssertEqual(doc.savedContents, modContent)
		let fcontents = try! String(contentsOfURL: (fileHandler?.fileCache.cachedFileUrl(file))!)
		XCTAssertEqual(fcontents, doc.currentContents)
	}
}

class MockAppStatus: NSObject, AppStatus {
	var currentProgress: NSProgress?
	var busy: Bool = false
	var statusMessage: NSString = ""
	var setCount:Int = 0
	
	func presentError(error: NSError, session:Session) {
		
	}
	
	func presentAlert(session:Session, message:String, details:String, buttons:[String], defaultButtonIndex:Int, isCritical:Bool, handler:((Int) -> Void)?)
	{
		
	}
	
}