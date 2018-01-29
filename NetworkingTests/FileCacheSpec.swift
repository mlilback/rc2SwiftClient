//
//  FileCacheSpec.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Quick
import Nimble
import ReactiveSwift
import Mockingjay
import URITemplate
import Result
import Model
import ClientCore
@testable import Networking

class FileCacheSpec: NetworkingBaseSpec {
	let baseUrlString = "http://localhost:9876"
	
	func stub(file: File, template: URITemplate) {
		let data = Data(bytes: Array<UInt8>(repeating: 1, count: file.fileSize))
		self.stub({ request in
			return template.extract(url: request.url!.absoluteString)!["fileId"] == String(file.id)
		}, builder: http(200, headers: ["Content-Length": String(file.id)], download: .content(data)))
	}
	
	override func spec() {
		let sessionConfig = URLSessionConfiguration.default
		sessionConfig.protocolClasses = [MockingjayProtocol.self] as [AnyClass] + sessionConfig.protocolClasses!
		let conInfo = try! ConnectionInfo(host: ServerHost.localHost, bulkInfoData: self.loadFileData("bulkInfo", fileExtension: "json")!, authToken: "dsfrsfsdfsdfsf", config: sessionConfig)
		let rawData = Data(bytes: Array<UInt8>(repeating: 1, count: 2048))
		let builder: (URLRequest) -> Response = { request in
//			return http(download: .streamContent(data: rawData, inChunksOf: 1024))(request)
			return http(download: .content(rawData))(request)
		}
		let fileTemplate = URITemplate(template: "\(baseUrlString)/file/{fileId}")

		describe("validate file cache") {
			var wspace: AppWorkspace!
			var fileCache: DefaultFileCache!
			
			beforeEach {
				let cacheDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
				wspace = try! conInfo.workspace(withId: 100, in: try! conInfo.project(withId: 100))
				fileCache = DefaultFileCache(workspace: wspace, baseUrl: URL(string: "\(self.baseUrlString)/")!, config: sessionConfig, queue: .global())
				fileCache.fileCacheUrl = cacheDir
				try! fileCache.fileManager.createDirectoryHierarchy(at: cacheDir)
				let matcher: (URLRequest) -> Bool = { request in
					return request.url!.path.hasPrefix("/file/")
				}
				self.stub(matcher, builder: builder)
			}
			
			afterEach {
				do { try FileManager.default.removeItem(at: fileCache.fileCacheUrl) } catch {}
			}
			
			it("single flushCache works") {
				let file = wspace.file(withId: 100)!
				expect(fileCache.isFileCached(file)).to(beFalse())
				let result = self.makeValueRequest(producer: fileCache.recache(file: file).logEvents(identifier: "loadFile"), queue: .global())
				expect(result.value).to(beCloseTo(1.0))
				expect(fileCache.isFileCached(file)).to(beTrue())
			}
			
			it("cacheAllFiles works") {
				wspace.files.forEach { self.stub(file: $0.model, template: fileTemplate) }
				let result = self.makeCompletedRequest(producer: fileCache.cacheAllFiles(), queue: .global())
				expect(result.error).to(beNil())
				for aFile in wspace.files {
					expect(fileCache.isFileCached(aFile)).to(beTrue())
				}
			}
			
			it("cache multiple files works") {
				let result = self.makeValueRequest(producer: fileCache.flushCache(files: wspace.files), queue: .global())
				expect(result.error).to(beNil())
				for aFile in wspace.files {
					expect(fileCache.isFileCached(aFile)).to(beTrue())
				}
			}

			it("validUrl downloads if not cached") {
				let file = wspace.file(withId: 100)!
				fileCache.flushCache(file: file)
				expect(fileCache.isFileCached(file)).to(beFalse())
				let result = self.makeValueRequest(producer: fileCache.validUrl(for: file), queue: .global())
				expect(result.error).to(beNil())
				let fdata = try! Data(contentsOf: result.value!)
				expect(fdata).to(equal(rawData))
			}

			it("validUrl doesn't download if already cached") {
				let file = wspace.file(withId: 100)!
				fileCache.flushCache(file: file)
				expect(fileCache.isFileCached(file)).to(beFalse())
				let customData = Data(bytes: Array<UInt8>(repeating: 122, count: 2048))
				try! customData.write(to: fileCache.cachedUrl(file: file))
				expect(fileCache.isFileCached(file)).to(beTrue())
				let result = self.makeValueRequest(producer: fileCache.validUrl(for: file), queue: .global())
				expect(result.error).to(beNil())
				let fdata = try! Data(contentsOf: result.value!)
				expect(fdata).to(equal(customData))
			}

			it("follows redirect") {
				let file = wspace.file(withId: 100)!
				expect(fileCache.isFileCached(file)).to(beFalse())
				let fakeUrlStr = "\(self.baseUrlString)/file/xxx"
				self.stub(uri(uri: fakeUrlStr), builder: http(304))
				self.stub(file: file.model, template: fileTemplate)
				let result = self.makeValueRequest(producer: fileCache.recache(file: file), queue: .global())
				expect(result.value).to(beCloseTo(1.0))
				expect(fileCache.isFileCached(file)).to(beTrue())
			}
		}
	}
}
