//
//  ModelSpec.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Quick
import Nimble
import ReactiveSwift
import Freddy
import NotifyingCollection
@testable import Networking

class ModelSpec: NetworkingBaseSpec {
	let fakeHost = ServerHost(name: "faketest", host: "festus.rc2.io")

	override func spec() {
		//since it is a struct, this can be copied every time
		let constantConInfo = try! ConnectionInfo(host: self.fakeHost, json: self.loadTestJson("loginResults"))
		var conInfo: ConnectionInfo?
		
		let loadData = {
			conInfo = constantConInfo
			conInfo = try! ConnectionInfo(host: self.fakeHost, json: self.loadTestJson("loginResults"))
			expect(conInfo).toNot(beNil())
		}
		
		describe("test loading of projects") {
			var proj: Project?
			var wspace: Workspace?
			
			beforeEach {
				loadData()
				proj = conInfo!.projects[1]
				expect(proj).toNot(beNil())
			}
			
			it("project loaded correctly") {
				expect(conInfo!.projects.count).to(equal(2))
				proj = conInfo!.projects[1]
				expect(proj).toNot(beNil())
				expect(proj!.name).to(equal("secondProject"))
				expect(proj!.projectId).to(equal(200))
				expect(proj!.workspaces.count).to(equal(2))
			}
			it("workspace loaded correctly") {
				wspace = proj!.workspaces[0]
				expect(wspace).toNot(beNil())
				expect(wspace!.name).to(equal("default"))
			}
			it("files loaded correctly") {
				expect(wspace!.files.count).to(equal(2))
				expect(wspace!.files[0].fileId).to(equal(201))
				expect(wspace!.files[0].name).to(equal("sample.R"))
			}
		}
		
		describe("workspace change notification") {
			var proj: Project?
			var wspace: Workspace?
			let updateJson = self.loadTestJson("modelChanges")
			var lastChanges: [CollectionChange<File>]?
			var fileDisposable: Disposable?
			
			beforeEach {
				loadData()
				lastChanges = nil
				proj = conInfo!.projects[1]
				expect(proj).toNot(beNil())
				wspace = proj?.workspace(withId: 201)
				expect(wspace).toNot(beNil())
				fileDisposable = wspace!.fileChangeSignal.observeValues { (changes) in
					lastChanges = changes
				}
			}
			afterEach {
				fileDisposable = nil
			}
			
			it("listen to file changes") {
				let json = updateJson["update_200_201_201"]
				expect(json).toNot(beNil())
				let updatedProject = try! Project(json: json!)
				proj?.addWorkspaceObserver(identifier: "test") { (wspace) -> Disposable? in
					return wspace.fileChangeSignal.observe { [weak self] event in
						guard let changes = event.value else { return }
						print("changes=\(changes)")
					}
				}
				expect{ try proj?.update(to: updatedProject) }.toNot(throwError())
				let file = wspace?.file(withId: 201)
				expect(file?.name).to(equal("sample2.R"))
			}
		}
	}
}

