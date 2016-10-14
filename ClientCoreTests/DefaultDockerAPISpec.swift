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
		beforeEach {
			sessionConfig = URLSessionConfiguration.default
			sessionConfig.protocolClasses = [MockingjayProtocol.self, DockerUrlProtocol.self] as [AnyClass] + sessionConfig.protocolClasses!
			self.stubGetRequest(uriPath: "/containers/json", fileName: "containers")
			api = DockerAPIImplementation(baseUrl: URL(string:"http://10.0.1.9:2375/")!, sessionConfig: sessionConfig)
		}
			
		describe("use api") {
			it("should refresh containers") {
				let scheduler = QueueScheduler(name: "\(#file)\(#line)")
				let producer = api.refreshContainers().observe(on: scheduler)
				var result: Result<[DockerContainer], NSError>?
				let group = DispatchGroup()
				
				let globalQueue = DispatchQueue.global()
				globalQueue.async(group: group) {
					result = producer.single()
					print("result=\(result)")
				}
				group.wait()
				expect(result?.error).to(beNil())
				expect(result?.value).toNot(beNil())
				let containers = result!.value!
				expect(containers).to(haveCount(3))
				expect(containers[.dbserver]).toNot(beNil())
				expect(containers[.dbserver]?.imageName).to(equal("rc2server/dbserver"))
				expect(containers[.dbserver]?.mountPoints).to(haveCount(1))
				expect(containers[.dbserver]?.mountPoints.first?.destination).to(equal("/rc2"))
				expect(containers[.appserver]).toNot(beNil())
				expect(containers[.appserver]?.state.value).to(equal(ContainerState.created))
			}
		}
	}
	
	///uses Mockingjay to stub out a request for uriPath with the contents of fileName.json
	func stubGetRequest(uriPath:String, fileName:String) {
		let path : String = Bundle(for: type(of:self)).path(forResource: fileName, ofType: "json")!
		let resultData = try? Data(contentsOf: URL(fileURLWithPath: path))
		stub(uri(uri: uriPath), builder: jsonData(resultData!))
	}

}
