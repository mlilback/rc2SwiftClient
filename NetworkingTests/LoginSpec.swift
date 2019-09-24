//
//  LoginSpec.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

// these tests require mockingjay

//import Foundation
//import Quick
//import Nimble
//import ReactiveSwift
//@testable import Networking
//import Mockingjay
//
//class LoginSpec: NetworkingBaseSpec {
//	let expectedToken = "dfsdghdfgsffgdsf"
//
//	override func spec() {
//		describe("validate login function") {
//			let sessionConfig = URLSessionConfiguration.default
//			sessionConfig.protocolClasses = [MockingjayProtocol.self] as [AnyClass] + sessionConfig.protocolClasses!
//			let fakeHost = ServerHost(name: "faketest", host: "festus.rc2.io")
//			let factory = LoginFactory(config: sessionConfig)
//
//			it("login success") {
//				let rawData = "{ \"token\": \"\(self.expectedToken)\" }".data(using: .utf8)
//				self.stub(self.postMatcher(uriPath: "/login"), builder: jsonData(rawData!))
//				let infoMatcher: (URLRequest) -> Bool = { request in
//					return request.url!.path.hasPrefix("/info")
//				}
//				self.stub(infoMatcher, builder: jsonData(self.loadFileData("bulkInfo", fileExtension: "json")!))
//				let producer = factory.login(to: fakeHost, as: "local", password: "local")
//				var conInfo: ConnectionInfo?
//				let group = DispatchGroup()
//				DispatchQueue.global().async(group: group) {
//					conInfo = producer.single()?.value
//				}
//				group.wait()
//				expect(conInfo?.authToken).to(equal(self.expectedToken))
//				expect(conInfo).toNot(beNil())
//				expect(conInfo?.user.id).to(equal(100))
//				expect(conInfo?.user.email).to(equal("singlesignin@rc2.io"))
//				expect(conInfo?.projects.value.count).to(equal(1))
//				//project testing in ModelSpec.swift
//			}
//		}
//	}
//
//	func postMatcher(uriPath: String) -> (URLRequest) -> Bool {
//		return { request in
//			return request.httpMethod == "POST" && request.url!.path.hasPrefix(uriPath)
//		}
//	}
//}
