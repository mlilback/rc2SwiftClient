//
//  LoginSpec.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Quick
import Nimble
import ReactiveSwift
import Result
@testable import Networking
import Mockingjay

class LoginSpec: NetworkingBaseSpec {
	override func spec() {
		describe("validate login function") {
			let sessionConfig = URLSessionConfiguration.default
			sessionConfig.protocolClasses = [MockingjayProtocol.self] as [AnyClass] + sessionConfig.protocolClasses!
			let fakeHost = ServerHost(name: "faketest", host: "festus.rc2.io")
			let factory = LoginFactory(config: sessionConfig)

			it("login success") {
				let rawData = self.loadFileData("loginResults", fileExtension: "json")
				self.stub(self.postMatcher(uriPath: "/login"), builder: jsonData(rawData!))
				let producer = factory.login(to: fakeHost, as: "local", password: "local")
				var conInfo: ConnectionInfo?
				let group = DispatchGroup()
				DispatchQueue.global().async(group: group) {
					conInfo = producer.single()?.value
				}
				group.wait()
				expect(conInfo).toNot(beNil())
				expect(conInfo?.user.userId).to(equal(100))
				expect(conInfo?.user.email).to(equal("singlesignin@rc2.io"))
				expect(conInfo?.projects.count).to(equal(1))
//				let proj = conInfo!.projects[0]
//				expect(proj.workspaces.value).to(equal(1))
			}
		}
	}

	func postMatcher(uriPath: String) -> (URLRequest) -> Bool {
		return { request in
			return request.httpMethod == "POST" && request.url!.path.hasPrefix(uriPath)
		}
	}
}
