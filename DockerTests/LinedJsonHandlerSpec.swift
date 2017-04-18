//
//  LinedJsonHandlerSpec.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Quick
import Nimble
import Freddy
@testable import Docker
import ClientCore

class LinedJsonHandlerSpec: QuickSpec {
	var lastMessageType: MessageType?
	var lastJson: [JSON] = []
	var jsonExpect: XCTestExpectation?
	var messageCount = 0
	
	override func spec() {
//		let crnl = Data(bytes: [UInt8(13), UInt8(10)])
		describe("") {
			
			context("with normal data") {
				beforeEach {
					self.jsonExpect = nil
					self.messageCount = 0
				}
			
				it("handles a proper response") {
					let rawData = self.loadFileData("linedNormal", fileExtension: "json")!
					let pipe = Pipe()
					let fh = pipe.fileHandleForReading
					self.jsonExpect = self.expectation(description: "finished reading")
					let testObj = LinedJsonHandler(fileHandle: fh, handler: self.testCallback)
					testObj.start()
					let writeFh = pipe.fileHandleForWriting
					writeFh.write(rawData)
					writeFh.closeFile()
					self.waitForExpectations(timeout: 10.0) { err in
						expect(err).to(beNil())
					}
					expect(self.lastMessageType).to(equal(MessageType.complete))
				}

				it("handles input with no CRNLCRNL") {
					let rawData = self.loadFileData("linedBadHeader", fileExtension: "json")!
					let pipe = Pipe()
					let fh = pipe.fileHandleForReading
					self.jsonExpect = self.expectation(description: "finished reading")
					let testObj = LinedJsonHandler(fileHandle: fh, handler: self.testCallback)
					testObj.start()
					let writeFh = pipe.fileHandleForWriting
					writeFh.write(rawData)
					writeFh.closeFile()
					self.waitForExpectations(timeout: 10.0) { err in
						expect(err).to(beNil())
					}
					expect(self.lastMessageType).to(equal(MessageType.complete))
				}

				//the following does not work because named pipes (like to docker) flush quickly. pipes in the same process cache up to 16K, so there is no way to test named pipes with internal pipes because of the buffers
				
//				it("handles data in chunks") {
//					let rawData = self.loadFileData("linedNormal", fileExtension: "json")!
//					let (headData, contentData) = try! HttpStringUtils.splitResponseData(rawData)
//					var lines = [Data]()
//					contentData.enumerateComponentsSeparated(by: crnl) { lineData in
//						lines.append(lineData)
//					}
//					let someLines = lines[0 ..< 10]
//					let pipe = Pipe()
//					let fh = pipe.fileHandleForReading
//					self.jsonExpect = self.expectation(description: "finished chunked reading")
//					let testObj = LinedJsonHandler(fileHandle: fh, handler: self.testCallback)
//					testObj.start()
//					let writeFh = pipe.fileHandleForWriting
//					headData.withUnsafeBytes({ (ptr: UnsafePointer<UInt8>) in
//						_ = Darwin.write(writeFh.fileDescriptor, ptr, headData.count)
//					})
//					//write each line in sequence (via delays) and wait until all written
//					var delay: TimeInterval = 0
//					let queue = DispatchQueue.global()
//					let group = DispatchGroup()
//					someLines.forEach { line in
//						queue.asyncAfter(deadline: .now() + delay) {
//							queue.async(group: group) {
//								line.withUnsafeBytes({ (ptr: UnsafePointer<UInt8>) in
//									_ = Darwin.write(writeFh.fileDescriptor, ptr, line.count)
//								})
//								delay += 0.1
//							}
//						}
//					}
//					group.wait()
//					writeFh.closeFile()
//					self.waitForExpectations(timeout: 10.0) { err in
//						expect(err).to(beNil())
//					}
//					expect(self.lastMessageType).to(equal(MessageType.complete))
//					expect(self.messageCount).to(equal(10))
//				}

//				it("handles an empty response") {
//					let pipe = Pipe()
//					let fh = pipe.fileHandleForReading
//					self.jsonExpect = self.expectation(description: "empty reading")
//					let testObj = LinedJsonHandler(fileHandle: fh, handler: self.testCallback)
//					testObj.start()
//					pipe.fileHandleForWriting.closeFile()
////					fh.closeFile()
//					self.waitForExpectations(timeout: 10.0) { _ in
//					}
//					expect(self.lastMessageType).to(equal(MessageType.complete))
//				}
			}
		}
	}

	func testCallback(msgType: MessageType?) {
		guard let msgType = msgType else { return }
		lastMessageType = msgType
		messageCount += 1
		switch msgType {
			case .json(let json):
				lastJson = json
				return
			case .headers(_):
				return
			default:
				jsonExpect?.fulfill()
		}
	}
	
	func urlForResource(fileName: String, fileExtension: String) -> URL {
		let bundle = Bundle(for: type(of: self))
		return bundle.url(forResource: fileName, withExtension: fileExtension)!
	}
	
	/// Load Data from a resource file
	///
	/// - Parameter fileName: name of the resource to load w/o file extension
	/// - Parameter fileExtension: the file extension of the resource to load
	/// - Returns: the Data object with the contents of the file
	func loadFileData(_ fileName: String, fileExtension: String) -> Data? {
		let bundle = Bundle(for: type(of: self))
		guard let url = bundle.url(forResource: fileName, withExtension: fileExtension),
			let data = try? Data(contentsOf: url)
			else
		{
			fatalError("failed to load \(fileName).\(fileExtension)")
		}
		return data
	}
}
