//
//  FileImporterTests.swift
//  SwiftClient
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import XCTest
@testable import MacClient
import Mockingjay
fileprivate func < <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l < r
  case (nil, _?):
    return true
  default:
    return false
  }
}

fileprivate func >= <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l >= r
  default:
    return !(lhs < rhs)
  }
}


var kvoContext:UInt8 = 1

class FileImporterTests: BaseTest, URLSessionDataDelegate {
	var expect:XCTestExpectation?
	var filesToImport:[FileToImport] = []
	var importer:FileImporter?
	var testWorkspace:Workspace!
	var expectedFiles:[String] = []

	override class func initialize() {
		URLSessionConfiguration.mockingjaySwizzleDefaultSessionConfiguration()
	}

	override func setUp() {
		super.setUp()
		filesToImport = fileUrlsForTesting().map() { return FileToImport(url: $0, uniqueName: nil) }
		testWorkspace = workspaceForTesting()
		expectedFiles = filesToImport.enumerate().map() { (index, file) in
			let jsonString = "{\"id\" : \(index),\"wspaceId\" : 1, " +
				"\"name\" : \"\(file.fileUrl.lastPathComponent!)\", \"version\" : 0," +
				"\"dateCreated\" : 1439407405827, \"lastModified\" : 1439407405827," +
				"\"fileSize\" : \(file.fileUrl.fileSize()),\"etag\" : \"f/1/0\" }"
			return jsonString
		}
//		testWorkspace.files = [testWorkspace.files.first!]
//		filesToImport = [filesToImport.first!]
	}

	override func tearDown() {
		importer = nil
		super.tearDown()
	}

	func testSingleFile() {
		filesToImport = [filesToImport.first!]
//		testSessionMock()
	}
	
//	func testSessionMock() {
////		let destUri = "/workspaces/1/file/upload"
////		stub(uri(destUri), builder:json(expectedFiles.first!, status: 201))
//		stub(everything, builder:jsonData(expectedFiles.first!.dataUsingEncoding(NSUTF8StringEncoding)!, status: 201))
//		
//		self.expect = self.expectationWithDescription("upload")
//		importer = FileImporter(filesToImport, workspace: testWorkspace, baseUrl:NSURL(string: "http://www.google.com/"), configuration: NSURLSessionConfiguration.defaultSessionConfiguration())
//		{_ in
//			self.expect?.fulfill()
//		}
//		importer?.progress.addObserver(self, forKeyPath: "completedUnitCount", options: .New, context: &kvoContext)
//		try! importer?.startImport()
//		self.waitForExpectationsWithTimeout(20) { _ in }
//		XCTAssertNil(importer?.progress.rc2_error)
//		XCTAssertEqual(testWorkspace.files.count, filesToImport.count)
//	}
	
	override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?)
	{
		guard keyPath != nil else {
			super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
			return
		}
		switch(keyPath!, context) {
			case("fractionCompleted", kvoContext):
				let percent = (object as? Progress)?.fractionCompleted
				print("per updated \(percent)")
				if percent >= 1.0 {
					expect?.fulfill()
				}
			
		case("completedUnitCount", kvoContext):
			let percent = (object as? Progress)?.fractionCompleted
			print("per updated \(percent)")
			if percent >= 1.0 {
				expect?.fulfill()
			}
			
			case("error", kvoContext):
				print("completed set to \(importer?.progress.rc2_error)")
				expect?.fulfill()
			
			default:
				super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
		}
	}
}

//protocol of functions we want to test
protocol URLSessionProtocol {
	func uploadTaskForFileURL(_ file:URL) -> URLSessionUploadTask
}

extension URLSession: URLSessionProtocol {
	func uploadTaskForFileURL(_ file:URL) -> URLSessionUploadTask
	{
		let task = uploadTask(with: URLRequest(url: URL(string: "http://www.apple.com/")!), fromFile: file)
		return task
	}
}

class FileImporterSession: NSObject, URLSessionProtocol {
	var realSession:URLSession
	
	init(configuration: URLSessionConfiguration, delegate sessionDelegate: URLSessionDelegate?, delegateQueue queue: OperationQueue?)
	{
		realSession = URLSession(configuration: configuration, delegate: sessionDelegate, delegateQueue: queue)
		super.init()
	}

	func randomDelay() -> Double {
		return Double(arc4random_uniform(50)) / 1000.0
	}
	
	func uploadTaskForFileURL(_ file:URL) -> URLSessionUploadTask
	{
		let myTask = realSession.uploadTask(with: URLRequest(url: URL(string: "http://www.apple.com/")!), fromFile: file)
		let fsize = Int64(file.fileSize())
		let halfSize = Int64(fsize / 2)
		let myDelegate = realSession.delegate as! URLSessionTaskDelegate
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
