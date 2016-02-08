//
//  BaseTest.swift
//  SwiftClient
//
//  Created by Mark Lilback on 2/8/16.
//  Copyright © 2016 Rc2. All rights reserved.
//

import XCTest
@testable import MacClient

class BaseTest: XCTestCase {

	var sessionData:LoginSession!
	var mockFM:MockFileManager!
	
	override func setUp() {
		super.setUp()
		//setup filemanager with directory to trash
		mockFM = MockFileManager()
		
		let path : String = NSBundle(forClass: RestServerTest.self).pathForResource("loginResults", ofType: "json")!
		let resultData = NSData(contentsOfFile: path)!
		sessionData = LoginSession(json: JSON.init(data: resultData), host: RestServer.sharedInstance.restHosts.first!)
	}
	
	override func tearDown() {
		mockFM = nil
		super.tearDown()
	}
}
