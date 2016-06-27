//
//  RestServerTest.swift
//  Rc2Client
//
//  Created by Mark Lilback on 12/16/15.
//  Copyright © 2015 West Virginia University. All rights reserved.
//

import XCTest
@testable import MacClient
import Mockingjay
import SwiftyJSON

class RestServerTest: XCTestCase {
	var server : RestServer?
	
	override func setUp() {
		super.setUp()
		NSURLSessionConfiguration.mockingjaySwizzleDefaultSessionConfiguration()
		server = RestServer()
		server?.selectHost("localhost")
	}
	
	override func tearDown() {
		super.tearDown()
	}

	func doLogin() {
		let path : String = NSBundle(forClass: RestServerTest.self).pathForResource("loginResults", ofType: "json")!
		let resultData = NSData(contentsOfFile: path)
		stub(http(.POST, uri: "/login"), builder: jsonData(resultData!))
		let loginEx = expectationWithDescription("login")
		server?.login("test", password: "beavis", handler: { (success, results, error) -> Void in
			XCTAssert(success, "login failed:\(error)")
			loginEx.fulfill()
		})
		self.waitForExpectationsWithTimeout(2) { (err) -> Void in }
	}
	
	func dummyWorkspace() -> Workspace {
		let path : String = NSBundle(forClass: RestServerTest.self).pathForResource("createWorkspace", ofType: "json")!
		let wspaceData = NSData(contentsOfFile: path)
		let wspaceJson = JSON(data: wspaceData!)
		let wspace = Workspace(json: wspaceJson)
		return wspace
	}
	
	func testDownloadImage() {
		let path : String = NSBundle(forClass: RestServerTest.self).pathForResource("loginResults", ofType: "json")!
		let resultData = NSData(contentsOfFile: path)
		let headers = ["Content-Type":"image/png"];
		stub(http(.GET, uri: "/workspaces/1/images/1"), builder:http(200, headers:headers, data:resultData))
		let imgExp = expectationWithDescription("imageDload")
		let wspace = dummyWorkspace()
		var rSuccess = false
		var rResults:Any?
		let destUrl = NSURL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: false)
		server?.downloadImage(wspace, imageId:1, destination: destUrl) { (success, results, error) in
			rSuccess = success
			rResults = results
			imgExp.fulfill()
		}
		self.waitForExpectationsWithTimeout(2){ (error) in }
		XCTAssertTrue(rSuccess)
		let returnedData = NSData(contentsOfURL: rResults as! NSURL)
		XCTAssertEqual(returnedData, resultData)
	}
	
	func testLoginData()
	{
		doLogin()
		XCTAssertNotNil(server?.loginSession)
		XCTAssertEqual("1_-6673679035999338665_-5094905675301261464", server!.loginSession!.authToken)
		XCTAssertEqual("Cornholio", server!.loginSession!.currentUser.lastName)
	}
	
	func testCreateWebsocketUrl() {
		server!.selectHost("localhost")
		let url = server!.createWebsocketUrl(2)
		let build = NSBundle(forClass: RestServer.self).infoDictionary!["CFBundleVersion"]!
		let queryStr = "client=osx&build=\(build)"
		XCTAssertEqual(url.query!, queryStr)
		XCTAssertEqual(url.host, "localhost")
		XCTAssertEqual(url.scheme, "ws")
		XCTAssertEqual(url.path, "/ws/2")
		XCTAssertEqual(url.port, 8088)
	}
	
	func testCreateSession() {
		doLogin()
		let wspace = dummyWorkspace()
		let session = server!.createSession(wspace, appStatus: DummyAppStatus())
		XCTAssertEqual(session.workspace, wspace)
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
	var currentProgress: NSProgress?
	var busy:Bool { return currentProgress != nil }
	var statusMessage: NSString = ""
	
	override init() {
		super.init()
	}
	
	func presentError(error: NSError, session:Session) {
		
	}
	
	func presentAlert(session:Session, message:String, details:String, buttons:[String], defaultButtonIndex:Int, isCritical:Bool, handler:((Int) -> Void)?)
	{
	}
	
}

