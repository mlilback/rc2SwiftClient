//
//  DockerContainerSpec.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Quick
import Nimble
import ReactiveSwift
@testable import DockerSupport

class DockerContainerSpec: QuickSpec {
	override func spec() {
		describe("test container parsing") {
			it("parse dbserver without version") {
				let ctype = ContainerType.from(imageName:"rc2server/dbserver")
				expect(ctype).to(equal(ContainerType.dbserver))
			}
			it("parse dbserver with version") {
				let ctype = ContainerType.from(imageName:"rc2server/dbserver:0.4")
				expect(ctype).to(equal(ContainerType.dbserver))
			}
			it("parse appserver") {
				let ctype = ContainerType.from(imageName:"rc2server/appserver")
				expect(ctype).to(equal(ContainerType.appserver))
			}
			it("parse compute") {
				let ctype = ContainerType.from(imageName:"rc2server/compute")
				expect(ctype).to(equal(ContainerType.compute))
			}
			it("parse compute with latest version") {
				let ctype = ContainerType.from(imageName:"rc2server/compute:latest")
				expect(ctype).to(equal(ContainerType.compute))
			}
			it("fail to parse invalid name") {
				let ctype = ContainerType.from(imageName:"rc2server/foobar:latest")
				expect(ctype).to(beNil())
			}
		}
	}
}
