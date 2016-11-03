//
//  DockerUrlProtocolTests.swift
//  SwiftClient
//
//  Created by Mark Lilback on 7/8/16.
//  Copyright © 2016 Rc2. All rights reserved.
//

import XCTest
import Freddy
import Darwin
import Nimble
@testable import ClientCore

class DockerUrlProtocolTests: XCTestCase, URLSessionDataDelegate {
	var sessionConfig: URLSessionConfiguration?
	var session: URLSession?
	var xpect: XCTestExpectation?
	var queue: OperationQueue = OperationQueue()
	
	override func setUp() {
		super.setUp()
		queue.underlyingQueue = DispatchQueue.global(qos: .userInitiated)
		continueAfterFailure = false
		sessionConfig = URLSessionConfiguration.default
		sessionConfig?.protocolClasses = [TestDockerProtocol.self, DockerUrlProtocol.self] as [AnyClass] + sessionConfig!.protocolClasses!
		sessionConfig?.timeoutIntervalForRequest = 5000
		session = URLSession(configuration: sessionConfig!, delegate: self, delegateQueue: queue)
//		xpect = expectation(description: "bg url")
	}
	
	override func tearDown() {
		super.tearDown()
	}

//	func testDispatchIO() {
//		let fexpect = expectation(description: "file reading")
//		let pipe = Pipe()
//		let readHandle = pipe.fileHandleForReading
//		let writeHandle = pipe.fileHandleForWriting
//		let queue = DispatchQueue(label: "io test")
//		let readSource = DispatchSource.makeReadSource(fileDescriptor: readHandle.fileDescriptor)
//		var readCount = 0
//		readSource.setEventHandler { 
//			let str = String(data: readHandle.availableData, encoding: .utf8)
//			print("read: \(str)")
//			readCount += 1
//		}
//		readSource.setCancelHandler { 
////			fexpect.fulfill()
//			print("canceled")
//		}
//		readSource.activate()
//		queue.asyncAfter(deadline: DispatchTime.now() + 0.1) {
//			writeHandle.write("foo1".data(using: .utf8)!)
//			sleep(1)
//			writeHandle.write("foo2".data(using: .utf8)!)
//			sleep(1)
//			writeHandle.write("foo3".data(using: .utf8)!)
//			sleep(1)
//			writeHandle.closeFile()
//			readSource.cancel()
//			fexpect.fulfill()
//		}
//		waitForExpectations(timeout: 10) { (err) in
//			expect(err).to(beNil())
//			expect(readCount).to(equal(3))
//		}
//	}

//	func testReadHandle() {
//		var observer: FHRead?
//		let fexpect = expectation(description: "file reading")
//		let pipe = Pipe()
//		let readHandle = pipe.fileHandleForReading
//		let writeHandle = pipe.fileHandleForWriting
//		observer = FHRead(expect: fexpect, fileHandle: readHandle)
//		readHandle.waitForDataInBackgroundAndNotify()
//		let queue = DispatchQueue(label: "io test")
//		queue.asyncAfter(deadline: DispatchTime.now() + 0.1) {
//			writeHandle.write("foo1".data(using: .utf8)!)
//			print("wrote 1")
//			sleep(1)
//			writeHandle.write("foo2".data(using: .utf8)!)
//			print("wrote 2")
//			sleep(1)
//			writeHandle.write("foo3".data(using: .utf8)!)
//			print("wrote 3")
//			sleep(1)
//			writeHandle.closeFile()
//			print("wrote close")
//			DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.1) {
//				readHandle.closeFile()
//			}
//		}
//		waitForExpectations(timeout: 10) { (err) in
//			expect(observer!.readCount).to(equal(3))
//			expect(err).to(beNil())
//			observer = nil
//		}
//	}

	// TODO: this doesn't work because we need to mock the communication to docker since it will always timeout
//	func testChunkedResponse() {
//		xpect = expectation(description: "foo bar")
//		let url = URL(string: "unix:///events")!
//		let request = NSMutableURLRequest(url: url)
//		request.rc2_chunkedResponse = true
//		let task = session?.dataTask(with: request as URLRequest)
//		task?.resume()
//		waitForExpectations(timeout: 5) { (error) in
//			expect(error).to(beNil())
//		}
//	}
	
//	func testVersionRequest() {
//		let expect = expectation(description: "contact docker daemon")
//		let url = URL(string: "unix:///version")!
//		var fetchedData:Data?
//		var httpResponse:HTTPURLResponse?
//		var error:NSError?
//		let task = session?.dataTask(with: URLRequest(url: url), completionHandler: { data, response, err in
//			error = err as NSError?
//			httpResponse = response as? HTTPURLResponse
//			fetchedData = data
//			expect.fulfill()
//		}) 
//		task?.resume()
//		self.waitForExpectations(timeout: 2) { (err) -> Void in
//			XCTAssertNil(error)
//			XCTAssertNotNil(httpResponse)
//			XCTAssertEqual(httpResponse!.statusCode, 200)
//			XCTAssertNotNil(fetchedData)
//			let jsonStr = String(data:fetchedData!, encoding: String.Encoding.utf8)!
//			let json = JSON.parse(jsonStr)
//		XCTAssertNotNil(json.dictionary)
//			let verStr = json["ApiVersion"].string
//			XCTAssertNotNil(verStr)
//			guard let verNum = Double(verStr!) else { XCTFail("failed to parse version number"); return }
//			XCTAssertNotNil(verNum >= 1.24)
//		}
//	}
//
	open func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void)
	{
		completionHandler(Foundation.URLSession.ResponseDisposition.allow)
	}
	
	open func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
		let str = String(data: data, encoding:String.Encoding.utf8)!
		print("got \(str)")
	}
	
	open func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		print("did complete")
		xpect?.fulfill()
	}

}

public class TestDockerProtocol: DockerUrlProtocol {
	override public func writeRequestData(data: Data, fileHandle: FileHandle) {
	}
}

class FHRead {
	let expect: XCTestExpectation
	var readCount = 0
	init(expect: XCTestExpectation, fileHandle: FileHandle) {
		self.expect = expect
		let nc = NotificationCenter.default
		nc.addObserver(self, selector: #selector(FHRead.dataRead(note:)), name: Notification.Name.NSFileHandleDataAvailable, object: fileHandle)
	}
	
//	deinit {
//		print("observer unregistered")
//		NotificationCenter.default.removeObserver(self)
//	}
	
	@objc func dataRead(note: Notification) {
		print("dataRead")
		guard let fh = note.object as? FileHandle else { fatalError() }
		let data = fh.availableData
		if data.count < 1 {
			print("end of data")
			expect.fulfill()
			return
		}
		print("read note called")
		let str = String(data: data, encoding: .utf8)
		readCount += 1
		print("read: \(str!) = \(readCount)")
		fh.waitForDataInBackgroundAndNotify()
	}
}

