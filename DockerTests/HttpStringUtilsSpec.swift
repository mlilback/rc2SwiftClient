//
//  HttpStringUtilsSpec.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Quick
import Nimble
@testable import Docker

class HttpStringUtilsSpec: QuickSpec {
	override func spec() {
		describe("test splitResponseData") {
			let crnlArray: [UInt8] = [13, 10]
			let doubleCrnl = Data(bytes: crnlArray + crnlArray)
			let dummy: [UInt8] = [45, 57, 62]
			let dummyData = Data(bytes: dummy)
			let strings = "someline\n sdfdsf s\n".data(using: .utf8)!

			it("should handle proper data") {
				var testData = strings
				testData.append(doubleCrnl)
				testData.append(dummyData)
				let (headData, contentData) = try! HttpStringUtils.splitResponseData(testData)
				expect(headData).to(equal(strings))
				expect(contentData).to(equal(dummyData))
			}
			
			it("should fail with no double crnl") {
				expect{ _ = try HttpStringUtils.splitResponseData(strings)}.to(throwError())
			}
			
			it("has no data") {
				expect{ _ = try HttpStringUtils.splitResponseData(Data())}.to(throwError())
			}
			
			it("has no content") {
				var testData = strings
				testData.append(doubleCrnl)
				let (headData, contentData) = try! HttpStringUtils.splitResponseData(testData)
				expect(headData).to(equal(strings))
				expect(contentData.count).to(equal(0))
			}
			
			it("has no header") {
				var testData = doubleCrnl
				testData.append(dummyData)
				let (headData, contentData) = try! HttpStringUtils.splitResponseData(testData)
				expect(headData.count).to(equal(0))
				expect(contentData).to(equal(dummyData))
			}
			
			it("content has double crnl") {
				var fakeData = dummyData
				fakeData.append(doubleCrnl)
				fakeData.append(dummyData)
				var testData = strings
				testData.append(doubleCrnl)
				testData.append(fakeData)
				let (headData, contentData) = try! HttpStringUtils.splitResponseData(testData)
				expect(headData).to(equal(strings))
				expect(contentData).to(equal(fakeData))
			}
		}
		
		describe("test extractHeaders") {
			//TODO: write tests
		}
	}
}
