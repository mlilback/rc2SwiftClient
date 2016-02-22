//
//  WorkspaceKVOTests.swift
//  SwiftClient
//
//  Created by Mark Lilback on 2/21/16.
//  Copyright © 2016 Rc2. All rights reserved.
//

import XCTest
@testable import MacClient

class WorkspaceKVOTests: BaseTest {
	var workspace:Workspace?
	var lastChange:WorkspaceFileChange?
	
	override func setUp() {
		super.setUp()
		workspace = sessionData.workspaces.first
		workspace!.filesArray.removeAllObjects()
		NSNotificationCenter.defaultCenter().addObserver(self, selector: "fileChangeNotification:", name: WorkspaceFileChangedNotification, object: workspace)
	}
	
	override func tearDown() {
		NSNotificationCenter.defaultCenter().removeObserver(self)
		workspace = nil //test dealloc
		super.tearDown()
	}

	func testWorkspaceFileKVO() {
		XCTAssertNil(lastChange)
		
	}

	func fileChangeNotificationHandler(note:NSNotification) {
		lastChange = note.userInfo!["change"] as? WorkspaceFileChange
	}
}
