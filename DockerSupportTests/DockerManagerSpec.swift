//
//  DockerManagerSpec.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Quick
import Nimble
import ReactiveSwift
import Mockingjay
import Result
import Freddy
import ClientCore
@testable import DockerSupport

class DockerManagerSpec: QuickSpec {
	override func spec() {
		let globalQueue = DispatchQueue.global()
		describe("test basic methods") {
			var sessionConfig: URLSessionConfiguration!
			var api: DockerAPI!
			beforeEach {
				sessionConfig = URLSessionConfiguration.default
				sessionConfig.protocolClasses = [MockingjayProtocol.self, DockerUrlProtocol.self] as [AnyClass] + sessionConfig.protocolClasses!
				
				api = DockerAPIImplementation(sessionConfig: sessionConfig)
			}

			//TODO: need mock userDefaults
//			it("manager can be created") {
//				let dm = DockerManager()
//				expect(dm).toNot(beNil())
//			}
			
			context("version info") {
				beforeEach {
					let path = Bundle(for: type(of: self)).path(forResource: "version", ofType: "json")
					let versionData = try! Data(contentsOf: URL(fileURLWithPath: path!))
					self.stub(uri(uri: "/version"), builder: jsonData(versionData))
				}

				it("fetch correct version information") {
					let producer = api.loadVersion()
					let result = self.makeValueRequest(producer: producer, queue: globalQueue)
					expect(result.error).to(beNil())
					expect(result.value).toNot(beNil())
					let version = result.value!
					expect(version.apiVersion).to(beCloseTo(1.24))
				}

				it("fetch json") {
					let producer = api.fetchJson(url: api.baseUrl.appendingPathComponent("/version"))
					let result = self.makeValueRequest(producer: producer, queue: globalQueue)
					expect(result.error).to(beNil())
					expect(result.value).toNot(beNil())
					expect(try! result.value!.getString(at: "ApiVersion")).to(equal("1.24"))
				}
			}
		}
	}

	func makeValueRequest<T>(producer: SignalProducer<T, Rc2Error>, queue: DispatchQueue) -> Result<T, Rc2Error> {
		var result: Result<T, Rc2Error>!
		let group = DispatchGroup()
		queue.async(group: group) {
			result = producer.single()
		}
		group.wait()
		return result
	}
	
	func makeNoValueRequest(producer: SignalProducer<(), Rc2Error>, queue: DispatchQueue) -> Result<(), Rc2Error> {
		var result: Result<(), Rc2Error>?
		let group = DispatchGroup()
		queue.async(group: group) {
			result = producer.wait()
		}
		group.wait()
		return result!
	}
}
