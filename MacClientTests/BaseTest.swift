//
//  BaseTest.swift
//  SwiftClient
//
//  Created by Mark Lilback on 2/8/16.
//  Copyright © 2016 Rc2. All rights reserved.
//

import XCTest
@testable import MacClient
import SwiftyJSON

class BaseTest: XCTestCase {

	var sessionData:LoginSession!
	var mockFM:MockFileManager!
	
	override func setUp() {
		super.setUp()
		//setup filemanager with directory to trash
		mockFM = MockFileManager()
		
		let path : String = NSBundle(forClass: RestServerTest.self).pathForResource("loginResults", ofType: "json")!
		let resultData = NSData(contentsOfFile: path)!
		sessionData = LoginSession(json: JSON.init(data: resultData), host: "test")
	}
	
	override func tearDown() {
		mockFM = nil
		super.tearDown()
	}
	
	func workspaceForTesting() -> Workspace {
		let path : String = NSBundle(forClass: self.dynamicType).pathForResource("createWorkspace", ofType: "json")!
		let json = try! String(contentsOfFile: path)
		let parsedJson = JSON.parse(json)
		return Workspace(json:parsedJson)
	}
	
	func fileUrlsForTesting() -> [NSURL] {
		let imgUrl = NSURL(fileURLWithPath: "/Library/Desktop Pictures/Art")
		let files = try! NSFileManager.defaultManager().contentsOfDirectoryAtURL(imgUrl, includingPropertiesForKeys: [NSURLFileSizeKey], options: [.SkipsHiddenFiles])
		return files
	}
}
