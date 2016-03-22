//
//  MacAppDelegate.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import XCGLogger
import Swinject

let log = XCGLogger.defaultInstance()

@NSApplicationMain
class MacAppDelegate: NSObject, NSApplicationDelegate, AppStatus {
	var loginWindowController: NSWindowController?
	var loginController: LoginViewController?
	var sessionWindowController: MainWindowController?
	
	func applicationWillFinishLaunching(notification: NSNotification) {
		log.setup(.Debug, showLogIdentifier: false, showFunctionName: true, showThreadName: false, showLogLevel: true, showFileNames: true, showLineNumbers: true, showDate: false, writeToFile: nil, fileLogLevel: .Debug)
		let cdUrl = NSBundle.mainBundle().URLForResource("CommonDefaults", withExtension: "plist")
		NSUserDefaults.standardUserDefaults().registerDefaults(NSDictionary(contentsOfURL: cdUrl!)! as! [String : AnyObject])
		RestServer.createServer(appStatus:self)
	}

	func applicationDidFinishLaunching(aNotification: NSNotification) {
		if NSProcessInfo.processInfo().environment["TestBundleLocation"] == nil {
			//skip login when running unit tests
			let sboard = NSStoryboard(name: "Main", bundle: nil)
			loginWindowController = sboard.instantiateControllerWithIdentifier("loginWindow") as? NSWindowController
			loginController = loginWindowController?.window?.contentViewController as? LoginViewController
			showLoginWindow()
		}
	}

	func applicationWillTerminate(aNotification: NSNotification) {
		// Insert code here to tear down your application
		NSNotificationCenter.defaultCenter().removeObserver(self)
	}

	func applicationShouldOpenUntitledFile(sender: NSApplication) -> Bool {
		return NSApp.modalWindow == nil
	}
	
	func applicationOpenUntitledFile(sender: NSApplication) -> Bool {
		showLoginWindow()
		return true
	}
	
	func attemptLogin(controller: LoginViewController) {
		RestServer.sharedInstance.selectHost(controller.selectedHost!)
		RestServer.sharedInstance.login(controller.loginName!, password: controller.password!) { (success, results, error) -> Void in
			if success {
				NSApp.stopModal()
				self.loginController!.loginAttemptComplete(nil)
				self.showSessionWindow()
			} else {
				self.loginController!.loginAttemptComplete(error!.localizedDescription)
			}
		}
	}
	
	func showSessionWindow() {
		updateStatus(nil)
		let sboard = SwinjectStoryboard.create(name: "MainController", bundle: nil)
		sessionWindowController = sboard.instantiateControllerWithIdentifier("sessionWindow") as? MainWindowController
		sessionWindowController?.window?.makeKeyAndOrderFront(self)
		//a bug in storyboard loading is causing DI to fail for the rootController when loaded via the window
		let root = sboard.instantiateControllerWithIdentifier("rootController") as? RootViewController
		sessionWindowController?.contentViewController = root
		sessionWindowController?.appStatus = self
		sessionWindowController?.setupChildren()
		NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(MacAppDelegate.sessionWindowWillClose), name: NSWindowWillCloseNotification, object: sessionWindowController!.window!)
	}
	
	func sessionWindowWillClose() {
		performSelector(#selector(MacAppDelegate.showLoginWindow), withObject: nil, afterDelay: 0.2)
	}
	
	func showLoginWindow() {
		//will be nil when running unit tests
		if loginController != nil {
			loginController!.hosts = RestServer.sharedInstance.restHosts
			loginController!.completionHandler = attemptLogin
			NSApp!.runModalForWindow((loginWindowController?.window)!)
		}
	}
	
	//MARK: AppStatus implementation
	private dynamic var _currentProgress: NSProgress?
	private var _statusLock: Spinlock = Spinlock()
	
	dynamic  var currentProgress: NSProgress? {
		get { return _statusLock.around({ return self._currentProgress }) }
	}
	
	dynamic var busy: Bool {
		get { return _statusLock.around({ return self._currentProgress != nil }) }
	}
	
	dynamic var statusMessage: NSString {
		get { return _statusLock.around({ return self._currentProgress != nil ? self._currentProgress?.localizedDescription! : "" })! }
	}

	func updateStatus(progress: NSProgress?) {
		if _currentProgress != nil && progress != nil {
			fatalError("can't set progress when there already is one")
		}
		_statusLock.around({ self._currentProgress = progress })
		NSNotificationCenter.defaultCenter().postNotificationNameOnMainThread(AppStatusChangedNotification, object: self)
		currentProgress?.rc2_addCompletionHandler() {
			self.updateStatus(nil)
		}
	}

}

extension SwinjectStoryboard {
	class func setup() {
		defaultContainer.registerForStoryboard(RootViewController.self) { r, c in
			c.appStatus = r.resolve(AppStatus.self, name:"root")
		}
		defaultContainer.registerForStoryboard(SidebarFileController.self) { r, c in
			c.appStatus = r.resolve(AppStatus.self, name:"file")
		}
		defaultContainer.register(AppStatus.self, name:"file") { _ in NSApp.delegate as! AppStatus }
		defaultContainer.register(AppStatus.self, name:"root") { _ in NSApp.delegate as! AppStatus }
	}
}
