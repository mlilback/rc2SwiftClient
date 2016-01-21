//
//  KeyValueObserverTests.swift
//  SwiftClient
//
//  Created by Mark Lilback on 1/21/16.
//  Copyright © 2016 Rc2. All rights reserved.
//

import XCTest
import Cocoa
@testable import MacClient

class KeyValueObserverTests: XCTestCase {

	override func setUp() {
		super.setUp()
		// Put setup code here. This method is called before the invocation of each test method in the class.
	}
	
	override func tearDown() {
		// Put teardown code here. This method is called after the invocation of each test method in the class.
		super.tearDown()
	}

	func testKVO() {
		let array: NSMutableArray = NSMutableArray(array: [1,2,3])
		let ac: NSArrayController = NSArrayController()
		ac.content = array
		var callCount = 0
		var context = ac.addKeyValueObserver("arrangedObjects", options:.New) {
			(source, keyPath, change) in
				print("got change \(array.count)")
				callCount += 1
		}
		XCTAssertEqual(ac.arrangedObjects.count, 3)
		ac.addObject("foo")
		XCTAssertEqual(ac.arrangedObjects.count, 4)
		ac.addObject("bar")
		XCTAssertEqual(ac.arrangedObjects.count, 5)
		ac.removeObject(ac.arrangedObjects[0])
		XCTAssertEqual(ac.arrangedObjects.count, 4)
		XCTAssertNotNil(context) //to stop compiler warning about not read
		context = nil
	}
}
