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
		
		beforeEach {
			json = self.loadTestJson("loginResults")
			conInfo = try! ConnectionInfo(host: ServerHost.localHost, json: json)
			if !(conInfo.urlSessionConfig.protocolClasses?.contains(where: {$0 == MockingjayProtocol.self}) ?? false) {
				conInfo.urlSessionConfig.protocolClasses = [MockingjayProtocol.self] as [AnyClass] + conInfo.urlSessionConfig.protocolClasses!
			}
			wspace = conInfo.project(withId: 100)!.workspace(withId: 100)!
			fakeDelegate = FakeSessionDelegate()
			fakeSocket = TestingWebSocket()
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
				let starter = session.open(session.createWebSocketRequest())
				let result = self.makeCompletedRequest(producer: starter)
				expect(result.error).to(beNil())
			}
		}
	}
}

