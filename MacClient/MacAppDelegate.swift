//
//  MacAppDelegate.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import XCGLogger
import SwinjectStoryboard
import Swinject

let log = XCGLogger.defaultInstance()

@NSApplicationMain
class MacAppDelegate: NSObject, NSApplicationDelegate {
	var sessionWindowControllers = Set<MainWindowController>()
	var bookmarkWindowController: NSWindowController?
	let bookmarkManager = BookmarkManager()
	private var appStatus: MacAppStatus?
	private var dockerManager: DockerManager?

	private dynamic var _currentProgress: NSProgress?
	private let _statusQueue = dispatch_queue_create("io.rc2.statusQueue", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0))

	func applicationWillFinishLaunching(notification: NSNotification) {
		dockerManager = DockerManager()
		appStatus = MacAppStatus(windowAccessor: windowForAppStatus)
		log.setup(.Debug, showLogIdentifier: false, showFunctionName: true, showThreadName: false, showLogLevel: true, showFileNames: true, showLineNumbers: true, showDate: false, writeToFile: nil, fileLogLevel: .Debug)
		let cdUrl = NSBundle.mainBundle().URLForResource("CommonDefaults", withExtension: "plist")
		NSUserDefaults.standardUserDefaults().registerDefaults(NSDictionary(contentsOfURL: cdUrl!)! as! [String : AnyObject])
		NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(MacAppDelegate.windowWillClose), name: NSWindowWillCloseNotification, object: nil)
	}

	func applicationDidFinishLaunching(aNotification: NSNotification) {
		//skip showing bookmarks when running unit tests
		guard NSProcessInfo.processInfo().environment["XCTestConfigurationFilePath"] == nil else { return }
		showBookmarkWindow(nil)
	#if HOCKEYAPP_ENABLED
		log.info("key is \(kHockeyAppIdentifier)")
		BITHockeyManager.sharedHockeyManager().configureWithIdentifier(kHockeyAppIdentifier)
		//BITHockeyManager.sharedHockeyManager().debugLogEnabled = true
		// Do some additional configuration if needed here
		BITHockeyManager.sharedHockeyManager().startManager()
	#endif
	}

	func applicationWillTerminate(aNotification: NSNotification) {
		NSNotificationCenter.defaultCenter().removeObserver(self, name: NSWindowWillCloseNotification, object: nil)
	}

	func applicationShouldOpenUntitledFile(sender: NSApplication) -> Bool {
		return NSApp.modalWindow == nil
	}
	
	func applicationOpenUntitledFile(sender: NSApplication) -> Bool {
		bookmarkWindowController?.window?.makeKeyAndOrderFront(self)
		return true
	}
	
	override func validateMenuItem(menuItem: NSMenuItem) -> Bool {
		switch(menuItem.action) {
			case #selector(MacAppDelegate.showBookmarkWindow(_:)):
				return NSApp.mainWindow != bookmarkWindowController?.window
			default:
				return false
		}
	}
	
	func windowForAppStatus(session:Session?) -> NSWindow {
		return windowControllerForSession(session!)!.window!
	}
	
	@IBAction func showBookmarkWindow(sender:AnyObject?) {
		if nil == bookmarkWindowController {
			let container = Container()
			container.registerForStoryboard(NSWindowController.self, name: "bmarkWindow") { r,c in
				log.info("wc registered")
			}
			container.registerForStoryboard(BookmarkViewController.self) { r, c in
				c.bookmarkManager = self.bookmarkManager
			}
			container.registerForStoryboard(AddBookmarkViewController.self) { r, c in
				c.bookmarkManager = self.bookmarkManager
			}
			container.registerForStoryboard(SelectServerViewController.self) { r, c in
				c.bookmarkManager = self.bookmarkManager
//				c.docker = self.dockerManager
			}

			let sboard = SwinjectStoryboard.create(name: "BookmarkManager", bundle: nil, container: container)
			bookmarkWindowController = sboard.instantiateControllerWithIdentifier("bookmarkWindow") as? NSWindowController
			let bvc = bookmarkWindowController!.contentViewController as! BookmarkViewController
			bvc.openSession = openSession
		}
		bookmarkWindowController?.window?.makeKeyAndOrderFront(self)
	}
	
	func openSession(restServer:RestServer) {
		appStatus!.updateStatus(nil)
		let wc = MainWindowController.createFromNib()
		sessionWindowControllers.insert(wc)
		
		let container = Container()
		container.registerForStoryboard(RootViewController.self) { r, c in
			c.appStatus = self.appStatus
		}
		container.registerForStoryboard(SidebarFileController.self) { r, c in
			c.appStatus = self.appStatus
		}
		container.registerForStoryboard(AbstractSessionViewController.self) { r, c in
			c.appStatus = self.appStatus
		}

		let sboard = SwinjectStoryboard.create(name: "MainController", bundle: nil, container: container)
		wc.window?.makeKeyAndOrderFront(self)
		//a bug in storyboard loading is causing DI to fail for the rootController when loaded via the window
		let root = sboard.instantiateControllerWithIdentifier("rootController") as? RootViewController
		wc.contentViewController = root
		wc.appStatus = self.appStatus
		wc.setupChildren(restServer)
	}
	
	func windowWillClose(note:NSNotification) {
		//if no windows will be visible, acitvate/show bookmark window
		if let sessionWC = (note.object as! NSWindow).windowController as? MainWindowController {
			sessionWindowControllers.remove(sessionWC)
			if sessionWindowControllers.count < 1 {
				performSelector(#selector(MacAppDelegate.showBookmarkWindow), withObject: nil, afterDelay: 0.2)
			}
		}
	}
	
	func windowControllerForSession(session:Session) -> MainWindowController? {
		for wc in sessionWindowControllers {
			if wc.session == session { return wc }
		}
		return nil
	}
}
