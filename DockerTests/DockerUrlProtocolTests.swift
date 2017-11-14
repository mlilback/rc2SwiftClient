//
//  DockerUrlProtocolTests.swift
//  Rc2Client
//
//  Created by Mark Lilback on 7/8/16.
//  Copyright © 2016 Rc2. All rights reserved.
//

import XCTest
import Freddy
import Darwin
import Nimble
@testable import Docker

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

	//TODO: fix so it is testing LinedJsonReader, not old method
//	func testDReader() {
//		let reader = DReader()
//		let exp = expectation(description: "foobar")
//		reader.startLoading(expect: exp)
//		waitForExpectations(timeout: 20.0) { err in
//			NSLog("exp fulfilled")
//		}
//	}
}

public class TestDockerProtocol: DockerUrlProtocol {
	override public func writeRequestData(data: Data, fileHandle: FileHandle) {
	}
}

class DReader {
	let socketPath = "/var/run/docker.sock"
	var lines: [JSON] = []
	var haveReadHeader = false
	var headers: String?
	
	func startLoading(expect: XCTestExpectation) {
		let fd = openDockerConnection()
		let readSrc = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DispatchQueue.global())
		let fh = FileHandle(fileDescriptor: fd)
		readSrc.setEventHandler {
			let sizeRead = readSrc.data
//			NSLog("read \(sizeRead) bytes")
			if sizeRead == 0 {
				expect.fulfill()
				readSrc.cancel()
				NSLog("got \(self.lines.count) messages")
				return
			}
//			let data = fh.readData(ofLength: Int(sizeRead))
//			let dataStr = String(data: data, encoding: .utf8)!
			if !self.haveReadHeader {
				//try reading the header from data
				
			}
//			NSLog("data: \(dataStr)")
//			NSLog("read \(data.count)")
		}
		readSrc.setCancelHandler {
			readSrc.cancel()
		}
		readSrc.resume()
		let outStr = "POST /images/create?fromImage=rc2server/appserver:0.4.3 HTTP/1.0\r\n\r\n"
		fh.write(outStr.data(using: .utf8)!)
	}
	
	func openDockerConnection() -> Int32 {
		let fd = socket(AF_UNIX, SOCK_STREAM, 0)
		guard fd >= 0 else {
			NSLog("error openign socket \(Darwin.errno)")
			XCTFail()
			return -1
		}
		let pathLen = socketPath.utf8CString.count
		precondition(pathLen < 104) //size limit of struct
		var addr = sockaddr_un()
		addr.sun_family = sa_family_t(AF_LOCAL)
		addr.sun_len = UInt8(pathLen)
		_ = withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
			strncpy(UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self), socketPath, pathLen)
		}
		//connect, make the request, and fetch result data
		var code: Int32 = 0
		withUnsafePointer(to: &addr) { ptr in
			ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { ar in
				code = connect(fd, ar, socklen_t(MemoryLayout<sockaddr_un>.size))
			}
		}
		guard code >= 0 else {
			NSLog("bad response \(code), \(errno)")
			XCTFail()
			return -1
		}
		return fd
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

