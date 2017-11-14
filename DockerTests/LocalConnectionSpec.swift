//
//  LocalConnectionSpec.swift
//  Rc2Client
//
//  Created by Mark Lilback on 4/13/17.
//  Copyright © 2017 Rc2. All rights reserved.
//

import Foundation
@testable import Docker
import os
import ClientCore
import Darwin
import Nimble
import XCTest

class LocalConnectionSpec: XCTestCase {
//	override func spec() {
//	}

//	var pipe: Pipe?
//	var readHandle: FileHandle?
//	var writeHandle: FileHandle?
//	var queue: DispatchQueue?
//	var readSource: DispatchSourceRead?
//	
//	override func setUp() {
//		queue = DispatchQueue(label: "io test")
//		pipe = Pipe()
//		readHandle = pipe!.fileHandleForReading
//		writeHandle = pipe!.fileHandleForWriting
//		let _ = fcntl(readHandle!.fileDescriptor, F_NOCACHE, 1)
//		let _ = fcntl(writeHandle!.fileDescriptor, F_NOCACHE, 1)
//		readSource = DispatchSource.makeReadSource(fileDescriptor: readHandle!.fileDescriptor, queue: queue!)
//	}
//	
//	override func tearDown() {
//		readSource?.cancel()
//		pipe = nil
//		readHandle = nil
//		writeHandle = nil
//		queue = nil
////		readSource = nil
//	}
//	
//	func testBusyBoxPull() {
//		let expect = expectation(description: "pull complete")
////		let rawData = try! Data(contentsOf: Bundle(for: DockerPullTest.self).url(forResource: "busybox", withExtension: "jsonData")!)
////		let completeStr = String(data: rawData, encoding: .ascii)!
////		let lines = completeStr.components(separatedBy: "\n")
////		let data = lines.map() { return ($0 + "\r\n").data(using: .utf8)! }
//		let processor = LinedJsonHandler(channel: readHandle, queue: queue!, jsonHandler: { (message) in
//			switch message {
//			case .completed:
//				expect.fulfill()
//			case .error(let error):
//				XCTFail("error: \(error)")
//			case .string(let str):
//				print(str)
//			}
//		})
//		processor.startHandler()
//		DispatchQueue.global().async {
//			let rawData = try! Data(contentsOf: Bundle(for: type(of: self)).url(forResource: "busybox1", withExtension: "txt")!)
//			self.writeHandle?.write(rawData)
//			DispatchQueue.global().asyncAfter(deadline: .now() + 0.20) {
//				let rawData = try! Data(contentsOf: Bundle(for: type(of: self)).url(forResource: "busybox2", withExtension: "txt")!)
//				self.writeHandle?.write(rawData)
//				DispatchQueue.global().asyncAfter(deadline: .now() + 0.20) {
//					let rawData = try! Data(contentsOf: Bundle(for: type(of: self)).url(forResource: "busybox3", withExtension: "txt")!)
//					self.writeHandle?.write(rawData)
//				}
//			}
//		}
//		waitForExpectations(timeout: 600, handler: nil)
//		//		let config = URLSessionConfiguration.default
//		//		config.protocolClasses = [TestDataProtocol.self, DockerUrlProtocol.self] as [AnyClass] + config.protocolClasses!
//		//		let url = URL(string: "test://foo.com/bar")!
//		//		let pullOp = DockerPullOperation(baseUrl: url, imageName: "busybox", estimatedSize: 667590, config: config)
//		//		let future = pullOp.pull() { progress in
//		//			self.unitCount = progress.currentSize
//		//		}
//		//		future.onSuccess { _ in
//		//			self.unitCount = pullOp.pullProgress.currentSize
//		//			self.expect!.fulfill()
//		//		}.onFailure { err in
//		//			self.savedError = err
//		//			self.expect!.fulfill()
//		//		}
//		//		waitForExpectations(timeout: 2) { err in
//		//			XCTAssertNil(self.savedError)
//		//			XCTAssertEqual(self.unitCount, 667590)
//		//		}
//		//	}
//	}

//	func testDispatchIO() {
//		let fexpect = expectation(description: "file reading")
//		var readCount = 0
//		readSource!.setEventHandler {
//			let str = String(data: self.readHandle!.availableData, encoding: .utf8)
//			print("read: \(str ?? "xxx")")
//			readCount += 1
//		}
//		readSource!.setCancelHandler {
//	//			fexpect.fulfill()
//			print("canceled")
//		}
//		readSource!.activate()
//		queue!.asyncAfter(deadline: DispatchTime.now() + 0.01) {
//			self.writeHandle!.write("foo1".data(using: .utf8)!)
//		}
//		queue!.asyncAfter(deadline: DispatchTime.now() + 0.02) {
//			self.writeHandle!.write("foo2".data(using: .utf8)!)
//		}
//		queue!.asyncAfter(deadline: DispatchTime.now() + 0.03) {
//			self.writeHandle!.write("foo3".data(using: .utf8)!)
//			self.queue!.asyncAfter(deadline: DispatchTime.now() + 0.01) {
//				self.writeHandle?.closeFile()
//				self.readHandle?.closeFile()
//				//			readSource.cancel()
//				fexpect.fulfill()
//			}
//		}
//		waitForExpectations(timeout: 10) { (err) in
//			expect(err).to(beNil())
//			expect(readCount).to(equal(3))
//		}
//	}
}
