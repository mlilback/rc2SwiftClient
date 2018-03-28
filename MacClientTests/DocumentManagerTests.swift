//
//  DocumentManagerTests.swift
//  Rc2Client
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import XCTest
import Quick
import Nimble
import ReactiveSwift
import Rc2Common
@testable import MacClient
@testable import Networking

class DocumentManagerTests: QuickSpec {
	private let (defaultLifetime, defaultToken) = Lifetime.make()
	
	override func spec() {
		var testWorkspace: AppWorkspace!
		var docManager: DocumentManager!
		var successSaver: SuccessfulFakeSaver!
		var conInfo: ConnectionInfo!
		var fileCache: FakeFileCache!
		let scheduler = QueueScheduler(targeting: DispatchQueue.global())

		describe("document manager") {
//			beforeEach {
				conInfo = self.fakeConInfo()
				testWorkspace = conInfo.defaultProject!.workspaces.value.first!
				successSaver = SuccessfulFakeSaver(workspace: testWorkspace)
				fileCache = FakeFileCache(workspace: testWorkspace, baseUrl: URL(fileURLWithPath: "/dev/null"))
				docManager = DocumentManager(fileSaver: successSaver, fileCache: fileCache, lifetime: self.defaultLifetime, notificationCenter: NotificationCenter(), wspaceCenter: NotificationCenter(), defaults: UserDefaults())
//			}

			let aFile = testWorkspace.files.first!
			var documentUpdated: Bool = false
			docManager.currentDocument.signal.observeValues { newDoc in
				documentUpdated = true
			}
			
			it("load document") {
				let fakeUrl = URL(fileURLWithPath: "/tmp/foo.txt")
				let fdata = self.loadFileData("lognormal", fileExtension: "R")!
				let fileInfo = FakeFileInfo(fileId: aFile.fileId, data: fdata, url: fakeUrl, cached: true)
				fileCache.fileInfo[aFile.fileId] = fileInfo
				var loaded = false
				let loadExpect = self.expectation(description: "load file")
				docManager.load(file: aFile).observe(on: scheduler).startWithResult { result in
					loaded = result.value != nil
					loadExpect.fulfill()
				}
				self.waitForExpectations(timeout: 2, handler: nil)
				expect(loaded).to(beTrue())
			}
			
			it("update with relevent info") {
				let change = AppWorkspace.FileChange(type: .modify, file: aFile)
				docManager.process(changes: [change])
				expect(documentUpdated).to(beTrue())
			}

			it("update with irrelevent info") {
				documentUpdated = false
				let change = AppWorkspace.FileChange(type: .remove, file: testWorkspace.files[1])
				docManager.process(changes: [change])
				expect(documentUpdated).to(beFalse())
			}
			
			it("save changes") {
				let doc = docManager.currentDocument.value!
				expect(doc.file.fileId).to(equal(aFile.fileId))
				let newContents = "foobar"
				doc.editedContents = newContents
				let saveExpect = self.expectation(description: "saving")
				docManager.save(document: doc).observe(on: scheduler).logEvents(identifier: "unit test").start { action in
					switch action {
						case .completed:
							saveExpect.fulfill()
						default:
							print("got \(action)")
					}
				}
				self.waitForExpectations(timeout: 2, handler: nil)
				expect(successSaver.savedContents).to(equal(newContents))
			}
		}
	}

	/// Load Data from a resource file
	///
	/// - Parameter fileName: name of the resource to load w/o file extension
	/// - Parameter fileExtension: the file extension of the resource to load
	/// - Returns: the Data object with the contents of the file
	func loadFileData(_ fileName: String, fileExtension: String) -> Data? {
		let bundle = Bundle(for: type(of: self))
		guard let url = bundle.url(forResource: fileName, withExtension: fileExtension),
			let data = try? Data(contentsOf: url)
			else
		{
			fatalError("failed to load \(fileName).\(fileExtension)")
		}
		return data
	}

	func fakeConInfo() -> ConnectionInfo {
		let data = loadFileData("bulkInfo", fileExtension: "json")!
		return try! ConnectionInfo(host: .localHost, bulkInfoData: data, authToken: "authtoken")
	}
}


class SuccessfulFakeSaver: FileSaver {
	let workspace: AppWorkspace
	var savedContents: String?
	
	init(workspace: AppWorkspace) {
		self.workspace = workspace
	}
	
	func save(file: AppFile, contents: String?) -> SignalProducer<Void, Rc2Error> {
		return SignalProducer<Void, Rc2Error> { observer, _ in
			self.savedContents = contents
			observer.sendCompleted()
		}.logEvents(identifier: "saver")
	}
}

class FailingFakeSaver: FileSaver {
	let workspace: AppWorkspace
	let error: Rc2Error
	
	init(workspace: AppWorkspace, error: Rc2Error = Rc2Error(type: .logic)) {
		self.workspace = workspace
		self.error = error
	}
	
	func save(file: AppFile, contents: String?) -> SignalProducer<Void, Rc2Error> {
		return SignalProducer<Void, Rc2Error> { observer, _ in
			observer.send(error: self.error)
		}
	}
}
