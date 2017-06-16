//
//  SessionSpec.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Quick
import Nimble
import ReactiveSwift
import Result
import Freddy
import ClientCore
import Mockingjay
@testable import Networking

class FakeSessionDelegate: SessionDelegate {
	///called when the session is closed. Called when explicity or remotely closed. Not called on application termination
	func sessionClosed() {
	}
	///called when a server response is received and not handled internally by the session
	func sessionMessageReceived(_ response: ServerResponse) {
	}
	///called when the server has returned an error. Delegate needs to associate it with the cause and error.
	func sessionErrorReceived(_ error: Rc2Error) {
	}
	///called when the initial caching/loading of files is complete
	func sessionFilesLoaded(_ session: Session) {
	}
	///a script/file had a call to help with the passed in arguments
	func respondToHelp(_ helpTopic: String) {
	}
}

class SessionSpec: NetworkingBaseSpec {
	override func spec() {
		var json: JSON!
		var conInfo: ConnectionInfo!
		var wspace: Workspace!
		var fakeDelegate: FakeSessionDelegate!
		var fakeSocket: TestingWebSocket!
		var fakeCache: FakeFileCache!
		var session: Session!
		let dummyBaseUrl = URL(string: "http://dev.rc2/")!
		var tmpDirectory: URL!
		
		beforeSuite {
			tmpDirectory = URL(string: UUID().uuidString, relativeTo: FileManager.default.temporaryDirectory)
			try! FileManager.default.createDirectory(at: tmpDirectory, withIntermediateDirectories: true, attributes: nil)
		}
		
		afterSuite {
			let _ = try? FileManager.default.removeItem(at: tmpDirectory)
		}
		
		beforeEach {
			json = self.loadTestJson("loginResults")
			conInfo = try! ConnectionInfo(host: ServerHost.localHost, json: json)
			if !(conInfo.urlSessionConfig.protocolClasses?.contains(where: {$0 == MockingjayProtocol.self}) ?? false) {
				conInfo.urlSessionConfig.protocolClasses = [MockingjayProtocol.self] as [AnyClass] + conInfo.urlSessionConfig.protocolClasses!
			}
			wspace = conInfo.project(withId: 100)!.workspace(withId: 100)!
			fakeDelegate = FakeSessionDelegate()
			fakeSocket = TestingWebSocket(url: URL(string: "ws://foo.com")!, protocols: [])
			fakeCache = FakeFileCache(workspace: wspace, baseUrl: dummyBaseUrl)
			session = Session(connectionInfo: conInfo, workspace: wspace, delegate: fakeDelegate, fileCache: fakeCache, webSocket: fakeSocket, queue: .global())
			//TODO: stub REST urls
			self.stub({ (request) -> (Bool) in
				return request.url?.absoluteString.hasPrefix(dummyBaseUrl.absoluteString) ?? false
			}, builder: http(200))
		}
		
		describe("query response with file") {
			it("connection opens") {
				//open the session
				let starter = session.open()
				let result = self.makeCompletedRequest(producer: starter)
				expect(result.error).to(beNil())
			}
		}
		
		describe("create file") {
			beforeEach {
				self.open(session: session)
			}
			it("success") {
				let updateJson = String(data: self.loadFileData("createdUpdate", fileExtension: "json")!, encoding: .utf8)!
				self.stub(uri(uri: "/workspaces/100/files/upload"), builder: { request in
					DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(100)) {
						fakeSocket.serverSent(updateJson)
					}
					return jsonData(self.loadFileData("createfile", fileExtension: "json")!, status: 201)(request)
				})
				fakeCache.fileInfo[212] = FakeFileInfo(fileId: 212, data: nil, url: tmpDirectory.appendingPathComponent("212.R"), cached: false)
				let createExpectation = self.expectation(description: "create file")
				var createdResult: Result<Int, Rc2Error>?
				session.create(fileName: "created.R") { result in
					createdResult = result
					createExpectation.fulfill()
				}
				self.waitForExpectations(timeout: 2.0, handler: nil)
				expect(createdResult?.error).to(beNil())
				expect(createdResult?.value).to(equal(212))
			}

			it("server error") {
				self.stub(uri(uri: "/workspaces/100/files/upload"), builder: http(500))
				let createExpectation = self.expectation(description: "create file")
				var createdResult: Result<Int, Rc2Error>?
				session.create(fileName: "created.R", timeout: 0.5) { result in
					createdResult = result
					createExpectation.fulfill()
				}
				self.waitForExpectations(timeout: 1.0, handler: nil)
				expect(createdResult?.error).toNot(beNil())
				expect(createdResult?.error?.type).to(equal(Rc2Error.Rc2ErrorType.network))
				expect(createdResult?.error?.nestedError).to( Predicate { expression in
					guard let actualVal = try expression.evaluate() as? NetworkingError else {
						return PredicateResult(status: .fail, message: ExpectationMessage.fail("networking error"))
					}
					if case .invalidHttpStatusCode(let rsp) = actualVal, rsp.statusCode == 500 {
						return PredicateResult(status: .matches, message: ExpectationMessage.expectedTo("http status is 500"))
					}
					return PredicateResult(status: .doesNotMatch, message: ExpectationMessage.expectedActualValueTo("be 500"))
				})
			}
		}
	}

	func open(session: Session) {
		let starter = session.open()
		let result = self.makeCompletedRequest(producer: starter)
		expect(result.error).to(beNil())
	}
	
	func cacheFiles(for wspace: Workspace, cache: FakeFileCache) {
		let bundle = Bundle(for: type(of: self))
		for aFile in wspace.files {
			let fileUrl = bundle.url(forResource: aFile.baseName, withExtension: aFile.fileType.fileExtension, subdirectory: "testFiles")!
			let data = try! Data(contentsOf: fileUrl)
			cache.fileInfo[aFile.fileId] = FakeFileInfo(fileId: aFile.fileId, data: data, url: nil, cached: false)
		}
	}
}


