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
	var sessionWindowControllers: [MainWindowController] = []
	var bookmarkWindowController: NSWindowController?

	private dynamic var _currentProgress: NSProgress?
	private let _statusQueue = dispatch_queue_create("io.rc2.statusQueue", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0))

	func applicationWillFinishLaunching(notification: NSNotification) {
		log.setup(.Debug, showLogIdentifier: false, showFunctionName: true, showThreadName: false, showLogLevel: true, showFileNames: true, showLineNumbers: true, showDate: false, writeToFile: nil, fileLogLevel: .Debug)
		let cdUrl = NSBundle.mainBundle().URLForResource("CommonDefaults", withExtension: "plist")
		NSUserDefaults.standardUserDefaults().registerDefaults(NSDictionary(contentsOfURL: cdUrl!)! as! [String : AnyObject])
	}

	func applicationDidFinishLaunching(aNotification: NSNotification) {
		//skip login when running unit tests
		guard NSProcessInfo.processInfo().environment["XCTestConfigurationFilePath"] == nil else {
			return
		}
		let sboard = NSStoryboard(name: "Main", bundle: nil)
		loginWindowController = sboard.instantiateControllerWithIdentifier("loginWindow") as? NSWindowController
		loginController = loginWindowController?.window?.contentViewController as? LoginViewController
		bookmarkWindowController = sboard.instantiateControllerWithIdentifier("bookmarkWindow") as? NSWindowController
		bookmarkWindowController?.window?.makeKeyAndOrderFront(self)
//		showLoginWindow(RestServer())
	}

	func applicationWillTerminate(aNotification: NSNotification) {
		// Insert code here to tear down your application
		NSNotificationCenter.defaultCenter().removeObserver(self)
	}

	func applicationShouldOpenUntitledFile(sender: NSApplication) -> Bool {
		return NSApp.modalWindow == nil
	}
	
	func applicationOpenUntitledFile(sender: NSApplication) -> Bool {
		bookmarkWindowController?.window?.makeKeyAndOrderFront(self)
//		showLoginWindow(RestServer())
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
//		showLoginWindow(RestServer())
	}
	
	func attemptLogin(controller: LoginViewController, userCanceled:Bool) {
//		guard !userCanceled else {
			NSApp.stopModal()
			loginWindowController?.window?.orderOut(self)
//			return
//		}
//		let restServer = RestServer()
//		restServer.selectHost(controller.selectedHost!)
//		restServer.login(controller.loginName, password: controller.password)
//		{ (success, results, error) in
//			if success {
//				NSApp.stopModal()
//				let wspace = restServer.loginSession!.projects[0].workspaceWithName(controller.selectedWorkspace!)!
//				restServer.createSession(wspace, appStatus: self)
//				self.loginController!.loginAttemptComplete(nil)
//				self.showSessionWindow(restServer)
//			} else {
//				self.loginController!.loginAttemptComplete(error!.localizedDescription)
//			}
//		}
	}
	
	func showSessionWindow(restServer:RestServer) {
		updateStatus(nil)
		let wc = MainWindowController.createFromNib()
		sessionWindowControllers.append(wc)
		
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
		wc.window?.makeKeyAndOrderFront(self)
		//a bug in storyboard loading is causing DI to fail for the rootController when loaded via the window
		let root = sboard.instantiateControllerWithIdentifier("rootController") as? RootViewController
		wc.contentViewController = root
		wc.appStatus = self
		wc.setupChildren(restServer)
		NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(MacAppDelegate.sessionWindowWillClose), name: NSWindowWillCloseNotification, object: wc.window!)
	}
	
	func sessionWindowWillClose() {
//		performSelector(#selector(MacAppDelegate.showLoginWindow), withObject: RestServer(), afterDelay: 0.2)
	}
	
	func showLoginWindow(restServer:RestServer) {
		//will be nil when running unit tests
		guard loginController != nil else { return }
//		loginController!.hosts = restServer.restHosts
		loginController!.completionHandler = attemptLogin
		NSApp!.runModalForWindow((loginWindowController?.window)!)
	}
	
	func windowControllerForSession(session:Session) -> MainWindowController? {
		for wc in sessionWindowControllers {
			if wc.session == session { return wc }
		}
		return nil
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

	func presentError(error: NSError, session:Session) {
		let alert = NSAlert(error: error)
		alert.beginSheetModalForWindow(windowControllerForSession(session)!.window!, completionHandler:nil)
	}
	
	func presentAlert(session:Session, message:String, details:String, buttons:[String], defaultButtonIndex:Int, isCritical:Bool, handler:((Int) -> Void)?)
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
		alert.beginSheetModalForWindow(windowControllerForSession(session)!.window!) { (rsp) in
			guard buttons.count > 1 else { return }
			dispatch_async(dispatch_get_main_queue()) {
				//convert rsp to an index to buttons
				handler?(rsp - NSAlertFirstButtonReturn)
			}
		}
	}

}
