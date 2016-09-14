//
//  EditorDocumentTests.swift
//  SwiftClient
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

// this is broken because EditorDocument.isLoaded is only set when network request returns. Need to use Mockingjay to properly implement these tests

import XCTest
@testable import MacClient

class EditorDocumentTests: BaseTest {
	var fileHandler:DefaultSessionFileHandler?
	var appStatus:MockAppStatus = MockAppStatus()
	var startFileContents:String = "file contents go here\n"
	var file:File!
	var fileUrl:URL!
	
	override func setUp() {
		super.setUp()
		let wspace = sessionData!.projects.first!.workspaces[0]
		file = wspace.files[0]
		let cacheDir = mockFM.tempDirUrl.appendingPathComponent("io.rc2.MacClient", isDirectory: true).appendingPathComponent("FileCache", isDirectory: true).absoluteURL
		try! mockFM.createDirectoryHierarchy(at: cacheDir)
		fileUrl = URL(fileURLWithPath: "\(file!.fileId).R", relativeTo: cacheDir).absoluteURL
		try! startFileContents.write(to: fileUrl, atomically: true, encoding: String.Encoding.utf8)
		fileHandler = DefaultSessionFileHandler(wspace: wspace, baseUrl: mockFM.tempDirUrl, config: URLSessionConfiguration.default, appStatus: appStatus)
		
	}
	
	override func tearDown() {
		super.tearDown()
	}

	func testSave() {
		XCTAssertEqual(appStatus.setCount, 0)
		let doc = EditorDocument(file: file, fileHandler: fileHandler!)
		//XCTAssertEqual(startFileContents, doc.savedContents)
		let modContent = "foo  bar \n baz"
		doc.willBecomeInactive(modContent)
		XCTAssertEqual(doc.currentContents, modContent)
		let expect = expectation(description: "save file")
		let prog = doc.saveContents()
		prog?.rc2_addCompletionHandler() {
			expect.fulfill()
		}
		self.waitForExpectations(timeout: 2){ (error) in }
		XCTAssertEqual(doc.savedContents, modContent)
		let fcontents = try! String(contentsOf: (fileHandler?.fileCache.cachedUrl(file:file))!)
		XCTAssertEqual(fcontents, doc.currentContents)
	}
}

class MockAppStatus: NSObject, AppStatus {
	var currentProgress: Progress?
	var busy: Bool = false
	var statusMessage: NSString = ""
	var setCount:Int = 0
	
	func presentError(_ error: NSError, session:Session?) {
		
	}
	
	func presentAlert(_ session:Session?, message:String, details:String, buttons:[String], defaultButtonIndex:Int, isCritical:Bool, handler:((Int) -> Void)?)
	{
		
	}
	
}
