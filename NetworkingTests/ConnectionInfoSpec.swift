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

// swiftlint:disable force_try

class ConnectionInfoSpec: NetworkingBaseSpec {
	let fakeHost = ServerHost(name: "faketest", host: "festus.rc2.io", user: "testuser")
	
	// swiftlint:disable function_body_length
	override func spec() {
		let bulkData = self.loadFileData("bulkInfo", fileExtension: "json")!
		// swiftlint: disable force_try
		let conInfo = try! ConnectionInfo(host: fakeHost, bulkInfoData: bulkData, authToken: "xcgvdsfsfsF")
		// swiftlint: disable force_try
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
				expect(project100.workspace(withId: 211)).to(beNil())
				let newWspace = Workspace(id: 211, version: 1, name: "added", userId: 1, projectId: 100, uniqueId: "123432234234", lastAccess: Date(), dateCreated: Date())
				var wspacesDict = conInfo.bulkInfo.workspaces
				var wspaces = wspacesDict[100]!
				wspaces.append(newWspace)
				wspacesDict[100] = wspaces
				let updatedBulk = BulkUserInfo(user: conInfo.bulkInfo.user, projects: conInfo.bulkInfo.projects, workspaces: wspacesDict, files: conInfo.bulkInfo.files)
				conInfo.update(bulkInfo: updatedBulk)
				expect(project100.workspaces.value.count).to(equal(wspaces.count))
				expect(project100.workspace(withId: newWspace.id)?.model).to(equal(newWspace))
			}

			it("remove file") {
				var rawFiles = conInfo.bulkInfo.files[wspace100.wspaceId]!
				let originalCount = rawFiles.count
				let removedFileId = rawFiles.last!.id
				rawFiles.removeLast()
				var fileDict = conInfo.bulkInfo.files
				fileDict[wspace100.wspaceId] = rawFiles
				let updatedBulk = BulkUserInfo(user: conInfo.bulkInfo.user, projects: conInfo.bulkInfo.projects, workspaces: conInfo.bulkInfo.workspaces, files: fileDict)
				conInfo.update(bulkInfo: updatedBulk)
				expect(wspace100.file(withId: removedFileId)).to(beNil())
				expect(wspace100.files.count).to(equal(originalCount - 1))
			}
			
			it("add and update file") {
				let newFile = File(id: 455, wspaceId: wspace100.wspaceId, name: "foobar.R", version: 2, dateCreated: Date(), lastModified: Date(), fileSize: 1201)
				var rawFiles = conInfo.bulkInfo.files[wspace100.wspaceId]!
				rawFiles.append(newFile)
				let updatingFile = wspace100.files.last!
				let updatedFile = File(id: updatingFile.fileId, wspaceId: updatingFile.wspaceId, name: "updatedFile.R", version: updatingFile.version + 1, dateCreated: updatingFile.dateCreated, lastModified: updatingFile.lastModified, fileSize: updatingFile.fileSize)
				let updateIndex = rawFiles.index(where: { $0.id == updatingFile.fileId })!
				rawFiles[updateIndex] = updatedFile
				var fileDict = conInfo.bulkInfo.files
				fileDict[wspace100.wspaceId] = rawFiles
				let updatedBulk = BulkUserInfo(user: conInfo.bulkInfo.user, projects: conInfo.bulkInfo.projects, workspaces: conInfo.bulkInfo.workspaces, files: fileDict)
				conInfo.update(bulkInfo: updatedBulk)
				// verify added file
				expect(wspace100.files.count).to(equal(rawFiles.count))
				expect(wspace100.file(withId: newFile.id)?.model).to(equal(newFile))
				// verify updated file
				expect(wspace100.file(withId: updatedFile.id)?.name).to(equal(updatedFile.name))
			}
			
			it("add and remove project") {
				let newProject = Project(id: 432, version: 1, userId: 100, name: "dummyproj")
				let newWspace = Workspace(id: 6534, version: 1, name: "newws", userId: 100, projectId: newProject.id, uniqueId: "sgdfsgsfasdfdsfsf", lastAccess: Date(), dateCreated: Date())
				let newFile1 = File(id: 542, wspaceId: newWspace.id, name: "file1.txt", version: 1, dateCreated: Date(), lastModified: Date(), fileSize: 121)
				let newFile2 = File(id: 1542, wspaceId: newWspace.id, name: "file2.Rmd", version: 1, dateCreated: Date(), lastModified: Date(), fileSize: 3121)
				var wspaces = conInfo.bulkInfo.workspaces
				wspaces[newProject.id] = [newWspace]
				var files = conInfo.bulkInfo.files
				files[newWspace.id] = [newFile1, newFile2]
				let updatedBulk = BulkUserInfo(user: conInfo.bulkInfo.user, projects: conInfo.bulkInfo.projects + [newProject], workspaces: wspaces, files: files)
				conInfo.update(bulkInfo: updatedBulk)
				// swiftlint:disable:next force_try
				let addedProj = try! conInfo.project(withId: newProject.id)
				expect(addedProj.model).to(equal(newProject))
				let addedWspace = addedProj.workspaces.value.first!
				expect(addedWspace.model).to(equal(newWspace))
				expect(addedWspace.files.count).to(equal(2))
				expect(addedWspace.file(withId: newFile1.id)?.model).to(equal(newFile1))
				expect(addedWspace.file(withId: newFile2.id)?.model).to(equal(newFile2))
				
				//remove the project
				// swiftlint:disable:next force_try
				let originalBulk: BulkUserInfo = try! conInfo.decode(data: bulkData)
				conInfo.update(bulkInfo: originalBulk)
				expect { try conInfo.project(withId: newProject.id) }.to(throwError())
			}
			
		}
	}
}
