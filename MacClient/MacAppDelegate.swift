//
//  MacAppDelegate.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import XCGLogger

let log = XCGLogger.defaultInstance()

@NSApplicationMain
class MacAppDelegate: NSObject, NSApplicationDelegate {
	var loginWindowController: NSWindowController?
	var loginController: LoginViewController?
	
	func applicationWillFinishLaunching(notification: NSNotification) {
		log.setup(.Debug, showLogIdentifier: false, showFunctionName: true, showThreadName: false, showLogLevel: true, showFileNames: true, showLineNumbers: true, showDate: false, writeToFile: nil, fileLogLevel: .Debug)
	}

	func applicationDidFinishLaunching(aNotification: NSNotification) {
		let sboard = NSStoryboard(name: "Main", bundle: nil)
		loginWindowController = sboard.instantiateControllerWithIdentifier("loginWindow") as? NSWindowController
		loginController = loginWindowController?.window?.contentViewController as? LoginViewController
		showLoginWindow()
	}

	func applicationWillTerminate(aNotification: NSNotification) {
		// Insert code here to tear down your application
	}

	func applicationShouldOpenUntitledFile(sender: NSApplication) -> Bool {
		return NSApp.modalWindow == nil
	}
	
	func applicationOpenUntitledFile(sender: NSApplication) -> Bool {
		showLoginWindow()
		return true
	}
	
	func attemptLogin(controller: LoginViewController) {
		NSApp.stopModal()
		loginController!.loginAttemptComplete(nil)
	}
	
	func showLoginWindow() {
		loginController!.hosts = RestServer.sharedInstance.restHosts
		loginController!.completionHandler = attemptLogin
		NSApp!.runModalForWindow((loginWindowController?.window)!)
	}
}

