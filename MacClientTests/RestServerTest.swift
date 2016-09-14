//
//  RestServerTest.swift
//  SwiftClient
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import XCTest
@testable import MacClient
import Mockingjay
import SwiftyJSON

class RestServerTest: XCTestCase {
	var server : RestServer?
	
	override func setUp() {
		super.setUp()
		URLSessionConfiguration.mockingjaySwizzleDefaultSessionConfiguration()
		server = RestServer(host: ServerHost(name: "local", host: "local", port: 8088, user: "local"))
	}
	
	override func tearDown() {
		super.tearDown()
	}

	func doLogin() {
		let path : String = Bundle(for: RestServerTest.self).path(forResource: "loginResults", ofType: "json")!
		let resultData = try? Data(contentsOf: URL(fileURLWithPath: path))
		stub(http(method: .post, uri: "/login"), builder: jsonData(resultData!))
		let loginEx = expectation(description: "login")
		let future = server?.login("local")
		var success = false
		var loginError: Error?
		future!.onSuccess { result in
			success = true
			loginEx.fulfill()
		}.onFailure { error in
			loginError = error
		}
		self.waitForExpectations(timeout: 2) { (err) -> Void in
			XCTAssertTrue(success)
			XCTAssertNil(loginError, "loign error: \(loginError!)")
		}
	}
	
	func dummyWorkspace() -> Workspace {
		let path : String = Bundle(for: type(of: self)).path(forResource: "createWorkspace", ofType: "json")!
		let json = try! String(contentsOfFile: path)
		let parsedJson = JSON.parse(json)
		let project = Project(json: parsedJson["projects"][0])
		return project.workspaces.first!
	}
	
//	func testDownloadImage() {
//		let path : String = NSBundle(forClass: RestServerTest.self).pathForResource("loginResults", ofType: "json")!
//		let resultData = NSData(contentsOfFile: path)
//		let headers = ["Content-Type":"image/png"];
//		stub(http(.GET, uri: "/workspaces/1/images/1"), builder:http(200, headers:headers, data:resultData))
//		let imgExp = expectationWithDescription("imageDload")
//		let wspace = dummyWorkspace()
//		var rSuccess = false
//		var rResults:Any?
//		let destUrl = NSURL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: false)
//		server?.downloadImage(wspace, imageId:1, destination: destUrl) { (success, results, error) in
//			rSuccess = success
//			rResults = results
//			imgExp.fulfill()
//		}
//		self.waitForExpectationsWithTimeout(2){ (error) in }
//		XCTAssertTrue(rSuccess)
//		let returnedData = NSData(contentsOfURL: rResults as! NSURL)
//		XCTAssertEqual(returnedData, resultData)
//	}
	
	func testLoginData()
	{
		doLogin()
		XCTAssertNotNil(server?.loginSession)
		XCTAssertEqual("1_-6673679035999338665_-5094905675301261464", server!.loginSession!.authToken)
		XCTAssertEqual("Account", server!.loginSession!.currentUser.lastName)
	}
	
	func testCreateWebsocketUrl() {
		let url = server!.createWebsocketUrl(2)
		let build = Bundle(for: RestServer.self).infoDictionary!["CFBundleVersion"]!
		let queryStr = "client=osx&build=\(build)"
		XCTAssertEqual(url.query!, queryStr)
		XCTAssertEqual(url.host, "local")
		XCTAssertEqual(url.scheme, "ws")
		XCTAssertEqual(url.path, "/ws/2")
		XCTAssertEqual(url.port, 8088)
	}
	
	func testCreateSession() {
		doLogin()
		let wspace = dummyWorkspace()
		XCTAssertNoThrow(expression: try server!.createSession(workspace:wspace, appStatus: DummyAppStatus()).onSuccess { session in
			XCTAssertEqual(session.workspace, wspace)
		})
	}
	/*
	func testCreateWorkspace() {
		doLogin()
		let path : String = NSBundle(forClass: RestServerTest.self).pathForResource("createWorkspace", ofType: "json")!
		let resultData = NSData(contentsOfFile: path)
		let wspaceEx = expectationWithDescription("wspace")
		stub(http(.POST, uri:"/workspaces"), builder:jsonData(resultData!))
		var wspace : Workspace? = nil
		server?.createWorkspace("foofy", handler: { (success, results, error) -> Void in
			XCTAssertTrue(success, "failed to create workspace:\(error)")
			wspace = results as? Workspace
			wspaceEx.fulfill()
		})
		self.waitForExpectationsWithTimeout(2){ (error) in }
		XCTAssertEqual(wspace!.name, "foofy", "wrong workspace name")
	}

	func testCreateDuplicateWorkspaceFails() {
		doLogin()
		let wspaceEx = expectationWithDescription("wspace")
		stub(http(.POST, uri:"/workspaces"), builder:http(422))
		server?.createWorkspace("foofy", handler: { (success, results, error) -> Void in
			XCTAssertFalse(success, "created duplicate workspace:\(error)")
			wspaceEx.fulfill()
		})
		self.waitForExpectationsWithTimeout(2){ (error) in }
	} */
}

class DummyAppStatus: NSObject, AppStatus {
	var currentProgress: Progress?
	var busy:Bool { return currentProgress != nil }
	var statusMessage: NSString = ""
	
	override init() {
		super.init()
	}
	
	func presentError(_ error: NSError, session:Session?) {
		
	}
	
	func presentAlert(_ session:Session?, message:String, details:String, buttons:[String], defaultButtonIndex:Int, isCritical:Bool, handler:((Int) -> Void)?)
	{
	}
	
}

