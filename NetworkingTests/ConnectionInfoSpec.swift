//
//  ConnectionInfoSpec.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Quick
import Nimble
import ReactiveSwift
import Model
@testable import Networking

class ConnectionInfoSpec: NetworkingBaseSpec {
	let fakeHost = ServerHost(name: "faketest", host: "festus.rc2.io")
	override func spec() {
		let bulkData = self.loadFileData("bulkInfo", fileExtension: "json")!
		let conInfo = try! ConnectionInfo(host: fakeHost, bulkInfoData: bulkData, authToken: "xcgvdsfsfsF")
		let project100 = try! conInfo.project(withId: 100)
		let wspace100 = project100.workspace(withId: 100)!
			
		it("project and workspaces exist") {
			expect(project100).toNot(beNil())
			expect(wspace100).toNot(beNil())
		}

		describe("updateable") {
			it("project name") {
				let oldName = conInfo.bulkInfo.projects[0].name
				let newName = oldName + "x"
				expect(project100.name).to(match(oldName))
				var projects = conInfo.bulkInfo.projects
				projects[0] = Project(id: project100.projectId, version: project100.version, userId: project100.userId, name: newName)
				let newBulk = BulkUserInfo(user: conInfo.bulkInfo.user, projects: projects, workspaces: conInfo.bulkInfo.workspaces, files: conInfo.bulkInfo.files)
				conInfo.update(bulkInfo: newBulk)
				expect(project100.name).to(match(newName))
			}
			
			it("remove workspace") {
				let wcount = project100.workspaces.value.count
				expect(wcount).to(beGreaterThan(1))
				var wspacesDict = conInfo.bulkInfo.workspaces
				var wspaces = wspacesDict[100]!
				let removed = wspaces.popLast()!
				wspacesDict[100] = wspaces
				let updatedBulk = BulkUserInfo(user: conInfo.bulkInfo.user, projects: conInfo.bulkInfo.projects, workspaces: wspacesDict, files: conInfo.bulkInfo.files)
				conInfo.update(bulkInfo: updatedBulk)
				expect(project100.workspaces.value.count).to(equal(wcount - 1))
				expect(project100.workspace(withId: removed.id)).to(beNil())
			}
			
			it("add workspace") {
				// TODO: implement
			}

			it("fail to remove last workspace") {
				// TODO: implement
			}
			
			it("remove file") {
				// TODO: implement
			}
			
			it("add and update file") {
				// TODO: implement
			}
			
			it("add project") {
				// TODO: implement
			}
			
			it("remove project") {
				// TODO: implement
			}
			
			it("fail to remove last project") {
				// TODO: implement
			}
		}
	}
}
