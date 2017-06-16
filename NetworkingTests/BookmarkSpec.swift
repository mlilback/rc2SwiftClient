//
//  BookmarkTest.swift
//  SwiftClient
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import XCTest
import Freddy
import Quick
import Nimble
@testable import Networking

class BookmarkSpec: NetworkingBaseSpec {
	override func spec() {
		it("bookmark serialization") {
			let server = ServerHost(name: "festus", host:"festus.rc2.io", port: 8088, user: "test", secure: false)
			let connectInfo = try! ConnectionInfo(host: server, json: self.loadTestJson("loginResults"))
			let wspace = connectInfo.project(withId: 100)!.workspace(withId: 100)!
			let original = Bookmark(connectionInfo: connectInfo, workspace: wspace, name: "test")
			let ostr = try! original.toJSON() .serializeString()
			expect(ostr).toNot(beNil())
			let ndict = try! JSON(jsonString: ostr)
			let newver = try! Bookmark(json: ndict)
			expect(original).to(equal(newver))
		}
	}
}
