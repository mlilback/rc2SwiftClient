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
class MacAppDelegate: NSObject, NSApplicationDelegate {
	var loginWindowController: NSWindowController?
	var loginController: LoginViewController?
	var sessionWindowController: MainWindowController?

	private dynamic var _currentProgress: NSProgress?
	private let _statusQueue = dispatch_queue_create("io.rc2.statusQueue", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0))

	func applicationWillFinishLaunching(notification: NSNotification) {
		log.setup(.Debug, showLogIdentifier: false, showFunctionName: true, showThreadName: false, showLogLevel: true, showFileNames: true, showLineNumbers: true, showDate: false, writeToFile: nil, fileLogLevel: .Debug)
		let cdUrl = NSBundle.mainBundle().URLForResource("CommonDefaults", withExtension: "plist")
		NSUserDefaults.standardUserDefaults().registerDefaults(NSDictionary(contentsOfURL: cdUrl!)! as! [String : AnyObject])
		RestServer.createServer(appStatus:self)
	}

	func applicationDidFinishLaunching(aNotification: NSNotification) {
		//skip login when running unit tests
		guard NSProcessInfo.processInfo().environment["TestBundleLocation"] == nil else {
			return
		}
		let sboard = NSStoryboard(name: "Main", bundle: nil)
		loginWindowController = sboard.instantiateControllerWithIdentifier("loginWindow") as? NSWindowController
		loginController = loginWindowController?.window?.contentViewController as? LoginViewController
		showLoginWindow()
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
	
	override func validateMenuItem(menuItem: NSMenuItem) -> Bool {
		switch(menuItem.action) {
			case #selector(MacAppDelegate.newDocument(_:)):
				return NSApp.modalWindow == nil
			default:
				return false
		}
	}
	
	@IBAction func newDocument(sender:AnyObject) {
		showLoginWindow()
	}
	
	func attemptLogin(controller: LoginViewController, userCanceled:Bool) {
		guard !userCanceled else {
			NSApp.stopModal()
			loginWindowController?.window?.orderOut(self)
			return
		}
		RestServer.sharedInstance.selectHost(controller.selectedHost!)
		RestServer.sharedInstance.login(controller.loginName, password: controller.password)
		{ (success, results, error) in
			if success {
				NSApp.stopModal()
				let wspace = RestServer.sharedInstance.loginSession!.workspaceWithName(controller.selectedWorkspace!)!
				NSNotificationCenter.defaultCenter().postNotificationNameOnMainThread(SelectedWorkspaceChangedNotification, object: Box(wspace))
				self.loginController!.loginAttemptComplete(nil)
				self.showSessionWindow()
			} else {
				self.loginController!.loginAttemptComplete(error!.localizedDescription)
			}
		}
	}
	
	func showSessionWindow() {
		updateStatus(nil)
		sessionWindowController = MainWindowController.createFromNib()

		let container = Container()
		container.registerForStoryboard(RootViewController.self) { r, c in
			c.appStatus = self as AppStatus
		}
		container.registerForStoryboard(SidebarFileController.self) { r, c in
			c.appStatus = self as AppStatus
		}
		container.registerForStoryboard(AbstractSessionViewController.self) { r, c in
			c.appStatus = self as AppStatus
		}

		let sboard = SwinjectStoryboard.create(name: "MainController", bundle: nil, container: container)
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
		guard loginController != nil else { return }
		loginController!.hosts = RestServer.sharedInstance.restHosts
		loginController!.completionHandler = attemptLogin
		NSApp!.runModalForWindow((loginWindowController?.window)!)
	}
}

//MARK: AppStatus implementation
extension MacAppDelegate: AppStatus {
	
	dynamic  var currentProgress: NSProgress? {
		get {
			var result: NSProgress? = nil
			dispatch_sync(_statusQueue) { result = self._currentProgress }
			return result
		}
		set { updateStatus(newValue) }
	}
	
	dynamic var busy: Bool {
		get {
			var result = false
			dispatch_sync(_statusQueue) { result = self._currentProgress != nil }
			return result
		}
	}
	
	dynamic var statusMessage: NSString {
		get {
			var status = ""
			dispatch_sync(_statusQueue) { status = self._currentProgress?.localizedDescription ?? "" }
			return status
		}
	}

	func updateStatus(progress: NSProgress?) {
		assert(_currentProgress == nil || progress == nil, "can't set progress when there already is one")
		dispatch_sync(_statusQueue) {
			self._currentProgress = progress
			self._currentProgress?.rc2_addCompletionHandler() {
				self.updateStatus(nil)
			}
		}
		NSNotificationCenter.defaultCenter().postNotificationNameOnMainThread(Notifications.AppStatusChanged, object: self)
	}

	func presentError(error: NSError) {
		let alert = NSAlert(error: error)
		alert.beginSheetModalForWindow(sessionWindowController!.window!, completionHandler:nil)
	}
	
	func presentAlert(message:String, details:String, buttons:[String], defaultButtonIndex:Int, isCritical:Bool, handler:((Int) -> Void)?)
	{
		let alert = NSAlert()
		alert.messageText = message
		alert.informativeText = details
		if buttons.count == 0 {
			alert.addButtonWithTitle(NSLocalizedString("Ok", comment: ""))
		} else {
			for aButton in buttons {
				alert.addButtonWithTitle(aButton)
			}
		}
		alert.alertStyle = isCritical ? .CriticalAlertStyle : .WarningAlertStyle
		alert.beginSheetModalForWindow(sessionWindowController!.window!) { (rsp) in
			guard buttons.count > 1 else { return }
			dispatch_async(dispatch_get_main_queue()) {
				//convert rsp to an index to buttons
				handler?(rsp - NSAlertFirstButtonReturn)
			}
		}
	}

}
