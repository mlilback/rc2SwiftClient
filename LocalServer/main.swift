//
//  main.swift
//  LocalServer
//
//  Created by Mark Lilback on 7/18/16.
//  Copyright © 2016 Rc2. All rights reserved.
//

import Foundation
import XCGLogger

let log = XCGLogger.defaultInstance()
log.setup(.Debug, showLogIdentifier: true, showFunctionName: true, showThreadName: true, showLogLevel: true, showFileNames: true, showLineNumbers: true, showDate: true, writeToFile: "/tmp/rc2.service.log")
let server = LocalDockerServer()
let listener = NSXPCListener.serviceListener()
listener.delegate = server;


autoreleasepool {
	let loopObserver = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.Entry.rawValue | CFRunLoopActivity.Exit.rawValue, true, 0,
	{ (observer, activity) in
		server.runLoopNotification(activity)
	})
	log.info("adding runloop observer")
	CFRunLoopAddObserver(CFRunLoopGetMain(), loopObserver, kCFRunLoopCommonModes);
	listener.resume()
}
