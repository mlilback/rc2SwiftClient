//
//  EditorDocumentTests.swift
//  SwiftClient
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import XCTest
@testable import MacClient

class EditorDocumentTests: BaseTest {
	var fileHandler:MockSessionFileHandler!
	var appStatus:MockAppStatus = MockAppStatus()
	var startFileContents:String = "file contents go here\n"
	var file:File!
	var fileUrl:NSURL!
	var testCacheDir: NSURL?
	
	override func setUp() {
		super.setUp()
		let wspace = sessionData!.projects.first!.workspaces[0]
		file = wspace.files[0]
		let cacheDir = mockFM.tempDirUrl.URLByAppendingPathComponent("io.rc2.MacClient", isDirectory: true)!.URLByAppendingPathComponent("FileCache", isDirectory: true)!.absoluteURL
		try! mockFM.createDirectoryAtURL(cacheDir!, withIntermediateDirectories: true, attributes: nil)
		testCacheDir = cacheDir
		fileUrl = NSURL(fileURLWithPath: "\(file!.fileId).R", relativeToURL: cacheDir).absoluteURL
		try! startFileContents.writeToURL(fileUrl, atomically: true, encoding: NSUTF8StringEncoding)
		fileHandler = MockSessionFileHandler(wspace:wspace, fileManager:mockFM)
		fileHandler.mockFileCache.append(file, url: fileUrl)
	}
	
	override func tearDown() {
		do {
			try mockFM.removeItemAtURL(testCacheDir!)
		} catch _ {
		}
		super.tearDown()
	}

	func testSave() {
		XCTAssertEqual(appStatus.setCount, 0)
		let saveExpect = expectationWithDescription("save")
		let doc = EditorDocument(file: file, fileHandler: fileHandler)
		doc.loadContents().onSuccess { _ in
			saveExpect.fulfill()
		}.onFailure { loadError in
			XCTFail("error loading contents: \(loadError)")
			saveExpect.fulfill()
		}
		waitForExpectationsWithTimeout(20) { error in
			guard error == nil else {XCTFail("failed to load document: \(error)"); abort() }
		}
		XCTAssertEqual(startFileContents, doc.savedContents)
		let modContent = "foo  bar \n baz"
		doc.willBecomeInactive(modContent)
		XCTAssertEqual(doc.currentContents, modContent)
		let expect = expectationWithDescription("save file")
		let prog = doc.saveContents()
		prog?.rc2_addCompletionHandler() {
			expect.fulfill()
		}
		self.waitForExpectationsWithTimeout(20){ (error) in }
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
	
	func presentError(error: NSError, session:Session?) {
		
	}
	
	func presentAlert(session:Session?, message:String, details:String, buttons:[String], defaultButtonIndex:Int, isCritical:Bool, handler:((Int) -> Void)?)
	{
		
	}
	
}
