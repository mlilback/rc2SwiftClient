//
//  FileImporterTests.swift
//  SwiftClient
//
//  Created by Mark Lilback on 2/17/16.
//  Copyright © 2016 Rc2. All rights reserved.
//

import XCTest
@testable import MacClient
import Mockingjay

var kvoContext:UInt8 = 1

class FileImporterTests: XCTestCase, NSURLSessionDataDelegate {
	var expect:XCTestExpectation?
	var filesToImport:[FileToImport] = []
	var importer:FileImporter?
	var testWorkspace:Workspace!

	override class func initialize() {
		NSURLSessionConfiguration.mockingjaySwizzleDefaultSessionConfiguration()
	}

	override func setUp() {
		super.setUp()
		let imgUrl = NSURL(fileURLWithPath: "/Library/Desktop Pictures/Art")
		let files = try! NSFileManager.defaultManager().contentsOfDirectoryAtURL(imgUrl, includingPropertiesForKeys: [NSURLFileSizeKey], options: [.SkipsHiddenFiles])
		filesToImport = files.map() { return FileToImport(url: $0, uniqueName: nil) }
		
		let path : String = NSBundle(forClass: self.dynamicType).pathForResource("createWorkspace", ofType: "json")!
		let json = try! String(contentsOfFile: path)
		let parsedJson = JSON.parse(json)
		testWorkspace = Workspace(json:parsedJson)
		testWorkspace.files = filesToImport.enumerate().map() { (index, file) in
			let jsonString = "{\"id\" : \(index),\"wspaceId\" : 1, " +
				"\"name\" : \"\(file.fileUrl.lastPathComponent!)\", \"version\" : 0," +
				"\"dateCreated\" : 1439407405827, \"lastModified\" : 1439407405827," +
				"\"fileSize\" : \(file.fileUrl.fileSize()),\"etag\" : \"f/1/0\" }"
			let json = JSON.parse(jsonString)
			return File(json: json)
		}
//		testWorkspace.files = [testWorkspace.files.first!]
//		filesToImport = [filesToImport.first!]
	}

	override func tearDown() {
		importer = nil
		super.tearDown()
	}

	func testSessionMock() {
//		let destUri = "/workspaces/1/file/upload"
//		stub(uri(destUri), builder:http(201))
		stub(everything, builder:http(201))
		
		self.expect = self.expectationWithDescription("upload")
		importer = FileImporter(filesToImport, workspace: testWorkspace) {
			self.expect?.fulfill()
		}
		try! importer?.startImport()
		self.waitForExpectationsWithTimeout(2) { _ in }
		XCTAssertNil(importer?.progress.rc2_error)
		XCTAssertEqual(testWorkspace.files.count, filesToImport.count)
	}
	
	override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>)
	{
		guard keyPath != nil else {
			super.observeValueForKeyPath(keyPath, ofObject: object, change: change, context: context)
			return
		}
		switch(keyPath!, context) {
			case("fractionCompleted", &kvoContext):
				let percent = (object as? NSProgress)?.fractionCompleted
				print("per updated \(percent)")
				if percent >= 1.0 {
					expect?.fulfill()
				}
			
			case("error", &kvoContext):
				print("completed set to \(importer?.progress.rc2_error)")
				expect?.fulfill()
			
			default:
				super.observeValueForKeyPath(keyPath, ofObject: object, change: change, context: context)
		}
	}
}

//protocol of functions we want to test
protocol URLSessionProtocol {
	func uploadTaskForFileURL(file:NSURL) -> NSURLSessionUploadTask
}

extension NSURLSession: URLSessionProtocol {
	func uploadTaskForFileURL(file:NSURL) -> NSURLSessionUploadTask
	{
		let task = uploadTaskWithRequest(NSURLRequest(URL: NSURL(string: "http://www.apple.com/")!), fromFile: file)
		return task
	}
}

class FileImporterSession: NSObject, URLSessionProtocol {
	var realSession:NSURLSession
	
	init(configuration: NSURLSessionConfiguration, delegate sessionDelegate: NSURLSessionDelegate?, delegateQueue queue: NSOperationQueue?)
	{
		realSession = NSURLSession(configuration: configuration, delegate: sessionDelegate, delegateQueue: queue)
		super.init()
	}

	func randomDelay() -> Double {
		return Double(arc4random_uniform(50)) / 1000.0
	}
	
	func uploadTaskForFileURL(file:NSURL) -> NSURLSessionUploadTask
	{
		let myTask = realSession.uploadTaskWithRequest(NSURLRequest(URL: NSURL(string: "http://www.apple.com/")!), fromFile: file)
		let fsize = Int64(file.fileSize())
		let halfSize = Int64(fsize / 2)
		let myDelegate = realSession.delegate as! NSURLSessionTaskDelegate
		delay(self.randomDelay())
		{
			//receive half the file's data
			myDelegate.URLSession!(self.realSession, task: myTask, didSendBodyData: halfSize, totalBytesSent: halfSize, totalBytesExpectedToSend: fsize)
			delay(self.randomDelay()) {
				//receive the other half
				myDelegate.URLSession!(self.realSession, task: myTask, didSendBodyData: halfSize, totalBytesSent: fsize, totalBytesExpectedToSend: fsize)
				myDelegate.URLSession!(self.realSession, task: myTask, didCompleteWithError: nil)
			}
		}
		return myTask
	}

}
