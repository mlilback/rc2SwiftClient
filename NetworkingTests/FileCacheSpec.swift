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
import Result
import ClientCore
@testable import Networking

class FileCacheSpec: NetworkingBaseSpec {
	override func spec() {
		let cacheDir = URL(fileURLWithPath: NSTemporaryDirectory())
		defer {
			do { try FileManager.default.removeItem(at: cacheDir) } catch {}
		}
		let sessionConfig = URLSessionConfiguration.default
		sessionConfig.protocolClasses = [MockingjayProtocol.self] as [AnyClass] + sessionConfig.protocolClasses!
		let rawData = Data(bytes: Array<UInt8>(repeating: 0, count: 2048))
		let builder: (URLRequest) -> Response = { request in
			return http(download: .streamContent(data: rawData, inChunksOf: 1024))(request)
		}
		let loginResultsJson = loadTestJson("loginResults")
		let cleanWspace = try! loginResultsJson.decode(at: "projects", 1, "workspaces", 0, type: Workspace.self)

		describe("validate file cache") {
			var wspace: Workspace!
			var fileCache: DefaultFileCache!
			
			beforeEach {
				wspace = Workspace(instance: cleanWspace)
				fileCache = DefaultFileCache(workspace: wspace, baseUrl: URL(string: "http://localhost:9876/")!, config: sessionConfig, queue: DispatchQueue.global())
				fileCache.fileCacheUrl = cacheDir
				let matcher: (URLRequest) -> Bool = { request in
					print("req=\(request.url)")
					return request.url!.path.hasPrefix("/workspaces/201/files/")
				}
				self.stub(matcher, builder: builder)
			}
			
			it("single flushCache works") {
				let file = wspace.file(withId: 202)!
				expect(fileCache.isFileCached(file)).to(beFalse())
				let result = self.makeValueRequest(producer: fileCache.recache(file: file), queue: DispatchQueue.global())
				expect(result.value).to(beCloseTo(1.0))
				expect(fileCache.isFileCached(file)).to(beTrue())
			}
			
			it("cacheAllFiles works") {
				let result = self.makeValueRequest(producer: fileCache.cacheAllFiles(), queue: DispatchQueue.global())
				expect(result.error).to(beNil())
				for aFile in wspace.files {
					expect(fileCache.isFileCached(aFile)).to(beTrue())
				}
			}
			
			it("cache multiple files works") {
				let result = self.makeValueRequest(producer: fileCache.flushCache(files: wspace.files), queue: DispatchQueue.global())
				expect(result.error).to(beNil())
				for aFile in wspace.files {
					expect(fileCache.isFileCached(aFile)).to(beTrue())
				}
			}
		}
	}
	
	func makeValueRequest<T>(producer: SignalProducer<T, Rc2Error>, queue: DispatchQueue) -> Result<T, Rc2Error>
	{
		var result: Result<T, Rc2Error>!
		let group = DispatchGroup()
		queue.async(group: group) {
			result = producer.last()
		}
		group.wait()
		return result
	}
}
