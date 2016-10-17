//
//  DefaultDockerAPISpec.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Quick
import Nimble
@testable import ClientCore
import Mockingjay
import Result
import ReactiveSwift

class DefaultDockerAPISpec: QuickSpec {
	override func spec() {
		var sessionConfig: URLSessionConfiguration!
		var api: DockerAPIImplementation!
		var globalQueue: DispatchQueue!
		let commonPrep = {
			globalQueue = DispatchQueue.global()
			sessionConfig = URLSessionConfiguration.default
			if !(sessionConfig.protocolClasses?.contains(where: {$0 == MockingjayProtocol.self}) ?? false) {
				sessionConfig.protocolClasses = [MockingjayProtocol.self, DockerUrlProtocol.self] as [AnyClass] + sessionConfig.protocolClasses!
			}
			api = DockerAPIImplementation(baseUrl: URL(string:"http://10.0.1.9:2375/")!, sessionConfig: sessionConfig)
		}
			
		describe("use docker api") {
			it("should refresh containers") {
				commonPrep()
				self.stubGetRequest(uriPath: "/containers/json", fileName: "containers")
				let result = self.loadContainers(api: api, queue: globalQueue)
				expect(result.error).to(beNil())
				expect(result.value).toNot(beNil())
				let containers = result.value!
				expect(containers).to(haveCount(3))
				expect(containers[.dbserver]).toNot(beNil())
				expect(containers[.dbserver]?.imageName).to(equal("rc2server/dbserver"))
				expect(containers[.dbserver]?.mountPoints).to(haveCount(1))
				expect(containers[.dbserver]?.mountPoints.first?.destination).to(equal("/rc2"))
				expect(containers[.appserver]).toNot(beNil())
				expect(containers[.appserver]?.state.value).to(equal(ContainerState.created))
			}
			
			context("use the dbserver container") {
				var dbcontainer: DockerContainer!
				beforeEach {
					commonPrep()
					self.stubGetRequest(uriPath: "/containers/json", fileName: "containers")
					let containers = self.loadContainers(api: api, queue: globalQueue).value
					guard let db = containers?[.dbserver] else {
						fatalError("failed to load containers for testing")
					}
					dbcontainer = db
					self.stub({ request in
						return request.httpMethod == "POST" && request.url!.path.hasPrefix("/containers/rc2_dbserver/")
					}, builder: http(204))
				}
				it("should correctly perform operations") {
					for anOperation in DockerContainerOperation.all {
						let scheduler = QueueScheduler(name: "\(#file)\(#line)")
						let producer = api.perform(operation: anOperation, container: dbcontainer).observe(on: scheduler)
						var result: Result<(), DockerError>?
						let group = DispatchGroup()
						globalQueue.async(group: group) {
							result = producer.wait()
						}
						group.wait()
						expect(result?.error).to(beNil())
					}
				}
			}
		}
	}
	
	func loadContainers(api: DockerAPI, queue:DispatchQueue) -> Result<[DockerContainer], DockerError> {
		let scheduler = QueueScheduler(name: "\(#file)\(#line)")
		let producer = api.refreshContainers().observe(on: scheduler)
		var result: Result<[DockerContainer], DockerError>?
		let group = DispatchGroup()
		
		 queue.async(group: group) {
			result = producer.single()
		}
		group.wait()
		guard let r = result else {
			fatalError("failed to get result from refreshContainers()")
		}
		return r
	}

	///uses Mockingjay to stub out a request for uriPath with the contents of fileName.json
	func stubGetRequest(uriPath:String, fileName:String) {
		let path : String = Bundle(for: type(of:self)).path(forResource: fileName, ofType: "json")!
		let resultData = try? Data(contentsOf: URL(fileURLWithPath: path))
		stub(uri(uri: uriPath), builder: jsonData(resultData!))
	}

}
