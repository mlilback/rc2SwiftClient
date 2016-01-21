//
//  Rc2SessionTests.swift
//  Rc2Client
//
//  Created by Mark Lilback on 1/9/16.
//  Copyright © 2016 West Virginia University. All rights reserved.
//

import XCTest
@testable import MacClient
import Starscream
import SwiftyJSON

class Rc2SessionTests: XCTestCase {
	static let wspaceJson = "[{\"id\":1, \"userId\":1, \"version\":1, \"name\":\"foofy\", \"files\":[]}]"
	static let jsonData = wspaceJson.dataUsingEncoding(NSUTF8StringEncoding)
	static let sjson = JSON(data: jsonData!)
	var wspace:Workspace?
	let delegate = TestDelegate()
	let wsSrc = MockWebSocket()
	var session: Session?

	override func setUp() {
		super.setUp()
		wspace = Workspace(json:Rc2SessionTests.sjson)
		session = Session(wspace!, delegate:delegate, source:wsSrc)
		wsSrc.session = session
	}
	
	override func tearDown() {
		super.tearDown()
	}

	func testSessionCreation() {
		XCTAssertNotNil(session)
		XCTAssertEqual(wspace, session!.workspace)
		XCTAssert(delegate === session!.delegate)
	}
	
	func testOpenCloseSession() {
		XCTAssertFalse(session!.connectionOpen)
		let openEx = expectationWithDescription("open session")
		delegate.expectation = openEx
		session!.open()
		waitForExpectationsWithTimeout(3) { (error) -> Void in
		}
		XCTAssertTrue(session!.connectionOpen)
		delegate.expectation = expectationWithDescription("close session")
		session!.close()
		waitForExpectationsWithTimeout(3) { (error) -> Void in
		}
		XCTAssertFalse(session!.connectionOpen)
	}

	func testSendMessage() {
		let dict = ["foo":"bar", "age":21]
		session!.sendMessage(dict)
		let jsonData = wsSrc.stringsWritten.last?.dataUsingEncoding(NSUTF8StringEncoding)
		let jsonObj = JSON(data:jsonData!)
		XCTAssertEqual(dict["foo"], jsonObj["foo"].stringValue)
		XCTAssertEqual(21, jsonObj["age"].int32Value)
	}
	
//	func testSendMessageFailure() {
//		let dict: Dictionary<String,AnyObject> = ["foo":wspace!, "bar":22]
//		let success = session!.sendMessage(dict)
//		XCTAssertFalse(success)
//	}
	
	func testReceiveMessage() {
		let json = "{\"foo\":11,\"bar\":\"baz\"}"
		session?.websocketDidReceiveMessage(wsSrc.socket, text: json)
		XCTAssertEqual(delegate.lastMessage!["foo"].intValue, 11)
		XCTAssertEqual(delegate.lastMessage!["bar"].stringValue, "baz")
	}
	
	func testVariablesVisible() {
		XCTAssertTrue(session?.variablesVisible == false)
		session?.variablesVisible = true
		XCTAssertTrue(session?.variablesVisible == true)
		let jsonData = wsSrc.stringsWritten.last?.dataUsingEncoding(NSUTF8StringEncoding)
		let jsonObj = JSON(data:jsonData!)
		XCTAssertEqual(jsonObj["cmd"].stringValue, "watchVariables")
		XCTAssertEqual(jsonObj["watch"].boolValue, true)
	}
	
	func testLookupInHelp() {
		session?.lookupInHelp("print")
		let json = JSON.parse(wsSrc.stringsWritten.last!)
		XCTAssertEqual(json["msg"], "help")
		XCTAssertEqual(json["topic"], "print")
	}
	
	func testClearVariablesAndExecuteScript() {
		//clear variables internally calls executeScript
		session?.clearVariables()
		let json = JSON.parse(wsSrc.stringsWritten.last!)
		XCTAssertEqual(json["msg"], "execute")
		XCTAssertEqual(json["code"], "rc2.clearEnvironment()")
	}
	
	func testExecuteScriptWithHelp() {
		let script = "x <- 23\nhelp(\"print\")\nc(1,3,4)"
		session?.executeScript(script)
		XCTAssertEqual(wsSrc.stringsWritten.count, 2)
		let json1 = JSON.parse(wsSrc.stringsWritten[0])
		XCTAssertEqual(json1["msg"], "help")
		XCTAssertEqual(json1["topic"], "print")
		let json2 = JSON.parse(wsSrc.stringsWritten[1])
		XCTAssertEqual(json2["msg"], "execute")
		XCTAssertEqual(json2["code"], "x <- 23\nc(1,3,4)")
	}
	
	func testExecuteFile() {
		session?.executeScriptFile(1);
		let json = JSON.parse(wsSrc.stringsWritten.last!)
		XCTAssertEqual(json["msg"], "execute")
		XCTAssertEqual(json["fileId"], 1)
	}

	func testUserList() {
		session?.requestUserList();
		let json = JSON.parse(wsSrc.stringsWritten.last!)
		XCTAssertEqual(json["msg"], "userList")
	}

	func testForceVariableRefresh() {
		session?.forceVariableRefresh();
		let json = JSON.parse(wsSrc.stringsWritten.last!)
		XCTAssertEqual(json["msg"], "watchVariables")
	}

	@objc class TestDelegate: NSObject, SessionDelegate {
		var expectation: XCTestExpectation?
		var lastMessage: JSON?
		func sessionOpened() {
			expectation?.fulfill()
		}
		func sessionClosed() {
			expectation?.fulfill()
		}
		func sessionMessageReceived(msg:JSON) {
			lastMessage = msg
		}
		func loadHelpItems(topic: String, items: [HelpItem]) {
		}
	}
	
	class MockWebSocket: WebSocketSource {
		var stringsWritten = [String]()
		let socket = DummyWebSocket()
		var session : Session?
		weak var delegate : WebSocketDelegate?
		
		func connect() {
			session?.websocketDidConnect(socket)
		}
		func disconnect(forceTimeout forceTimeout: NSTimeInterval?) {
			session?.websocketDidDisconnect(socket, error: nil)
		}
		func writeString(str: String) {
			stringsWritten.append(str)
		}
		func writeData(data: NSData) {
		}
		func writePing(data: NSData) {
		}
	}
	
	class DummyWebSocket : WebSocket {
		init() {
			super.init(url: NSURL(fileURLWithPath: "/dev/null"))
		}
	}
}
