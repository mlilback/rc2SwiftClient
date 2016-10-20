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
import SwiftyJSON
@testable import ClientCore

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
					expect(result.value!["ApiVersion"].string).to(equal("1.24"))
				}
			}
			
			context("test network operations") {
				beforeEach {
					let path = Bundle(for: type(of: self)).path(forResource: "networks", ofType: "json")
					let networkData = try! Data(contentsOf: URL(fileURLWithPath: path!))
					self.stub(uri(uri: "/networks"), builder: jsonData(networkData))
					self.stub({ req in
						print("url=\(req.url)")
						return true
					}, builder: { (req) in
						return Response.success(HTTPURLResponse(url: req.url!, statusCode: 201, httpVersion: "HTTP/1.1", headerFields: nil)!, .noContent)
					})
				}
				
				it("network exists") {
					let result = self.makeValueRequest(producer: api.networkExists(name: "rc2server"), queue: globalQueue)
					expect(result.error).to(beNil())
					expect(result.value).toNot(beNil())
					expect(result.value!).to(beTrue())
				}
				
				it("create network") {
					self.stub(uri(uri: "/networks/create"), builder: http(201))
					let result = self.makeNoValueRequest(producer: api.create(network: "rc2test"), queue: globalQueue)
					expect(result.error).to(beNil())
					//value will be nil since nothing is returned
				}
			}
		}
	}

	func makeValueRequest<T>(producer: SignalProducer<T, DockerError>, queue: DispatchQueue) -> Result<T, DockerError> {
		var result: Result<T, DockerError>!
		let group = DispatchGroup()
		queue.async(group: group) {
			result = producer.single()
		}
		group.wait()
		return result
	}
	
	func makeNoValueRequest(producer: SignalProducer<(), DockerError>, queue: DispatchQueue) -> Result<(), DockerError> {
		var result: Result<(), DockerError>?
		let group = DispatchGroup()
		queue.async(group: group) {
			result = producer.wait()
		}
		group.wait()
		return result!
	}
}
