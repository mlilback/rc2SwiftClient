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
	var closeNotificationToken: AnyObject?
	
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
		updateStatus(false, message: "")
		let sboard = SwinjectStoryboard.create(name: "MainWindow", bundle: nil)
		sessionWindowController = sboard.instantiateControllerWithIdentifier("sessionWindow") as? MainWindowController
		sessionWindowController?.window?.makeKeyAndOrderFront(self)
		//a bug in storyboard loading is causing DI to fail for the rootController when loaded via the window
		let root = sboard.instantiateControllerWithIdentifier("rootController") as? RootViewController
		sessionWindowController?.contentViewController = root
		sessionWindowController?.appStatus = self
		sessionWindowController?.setupChildren()
		closeNotificationToken = NSNotificationCenter.defaultCenter().addObserverForName(NSWindowWillCloseNotification, object: sessionWindowController!.window!, queue: NSOperationQueue.mainQueue())
		{ [weak self] (note) -> Void in
			self?.closeNotificationToken = nil
			self?.performSelector("showLoginWindow", withObject: nil, afterDelay: 0.2)
		}
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
	private dynamic var _busy: Bool = false
	private dynamic var _status: NSString = ""
	private var _cancelHandler: ((appStatus:AppStatus) -> Bool)?
	private var lock: Spinlock = Spinlock()
	
	dynamic var busy: Bool {
		get { return lock.around({ return self._busy }) }
	}
	
	dynamic var statusMessage: NSString {
		get { return lock.around({ return self._status}) }
	}

	var cancelHandler: ((appStatus:AppStatus) -> Bool)? {
		get { return _cancelHandler }
	}
	
	func updateStatus(busy:Bool, message:String, cancelHandler:((appStatus:AppStatus) -> Bool)?) {
		guard busy != _busy else { return } //do nothing if busy not changing
		lock.around({
			self._status = message
			self._busy = busy
			self._cancelHandler = cancelHandler
		})
		NSNotificationCenter.defaultCenter().postNotificationName(AppStatusChangedNotification, object: self)
	}

}

extension SwinjectStoryboard {
	class func setup() {
		defaultContainer.registerForStoryboard(RootViewController.self) { r, c in
			c.appStatus = r.resolve(AppStatus.self, name:"root")
		}
		defaultContainer.registerForStoryboard(FileViewContrfoller.self) { r, c in
			c.appStatus = r.resolve(AppStatus.self, name:"file")
		}
		defaultContainer.register(AppStatus.self, name:"file") { _ in NSApp.delegate as! AppStatus }
		defaultContainer.register(AppStatus.self, name:"root") { _ in NSApp.delegate as! AppStatus }
	}
}
