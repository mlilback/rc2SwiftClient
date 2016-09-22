//
//  MacAppDelegate.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import os
import SwinjectStoryboard
import Swinject
import SwiftyJSON
import ClientCore

//let log = XCGLogger.defaultInstance()

@NSApplicationMain
class MacAppDelegate: NSObject, NSApplicationDelegate {
	var sessionWindowControllers = Set<MainWindowController>()
	var bookmarkWindowController: NSWindowController?
	let bookmarkManager = BookmarkManager()
	dynamic var dockerManager: DockerManager?
	var setupController: ServerSetupController?

	fileprivate dynamic var _currentProgress: Progress?
	fileprivate let _statusQueue = DispatchQueue(label: "io.rc2.statusQueue", qos: .userInitiated)

	func applicationWillFinishLaunching(_ notification: Notification) {
		dockerManager = DockerManager()
		dockerManager!.isDockerRunning().onSuccess { _ in
			self.dockerManager!.checkForImageUpdate().onSuccess { _ in
				os_log("docker is running")
				DispatchQueue.main.async {
					self.startSetup()
				}
			}.onFailure { err in
				os_log("error checking for docker image update: %{public}s", err)
			}
		}.onFailure { err in
			os_log("docker not running: %{public}s", type:.error, err as NSError)
		}
		let cdUrl = Bundle.main.url(forResource: "CommonDefaults", withExtension: "plist")
		UserDefaults.standard.register(defaults: NSDictionary(contentsOf: cdUrl!)! as! [String : AnyObject])
		NotificationCenter.default.addObserver(self, selector: #selector(MacAppDelegate.windowWillClose), name: NSNotification.Name.NSWindowWillClose, object: nil)
	}

	func applicationDidFinishLaunching(_ aNotification: Notification) {
		//skip showing bookmarks when running unit tests
		guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
//		showBookmarkWindow(nil)
	#if HOCKEYAPP_ENABLED
//		log.info("key is \(kHockeyAppIdentifier)")
//		BITHockeyManager.sharedHockeyManager().configureWithIdentifier(kHockeyAppIdentifier)
		//BITHockeyManager.sharedHockeyManager().debugLogEnabled = true
		// Do some additional configuration if needed here
//		BITHockeyManager.sharedHockeyManager().startManager()
	#endif
		restoreSessions()
	}

	func applicationWillTerminate(_ aNotification: Notification) {
		NotificationCenter.default.removeObserver(self, name: NSNotification.Name.NSWindowWillClose, object: nil)
		let defaults = UserDefaults.standard
		//save info to restore open sessions
		var reopen = [Bookmark]()
		for controller in sessionWindowControllers {
			if let session = controller.session, let rest = session.restServer, let proj = session.workspace.project {
				let bmark = Bookmark(name: "irrelevant", server: rest.host, project: proj.name, workspace: session.workspace.name)
				reopen.append(bmark)
			}
		}
		do {
			let bmarks = try JSON(reopen.map() { try $0.serialize() })
			defaults.set(bmarks.rawString(), forKey: PrefKeys.OpenSessions)
		} catch let err {
			os_log("failed to serialize bookmarks: %{public}@", type:.error, err as NSError)
		}
	}

	func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
		return NSApp.modalWindow == nil
	}
	
	func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
		bookmarkWindowController?.window?.makeKeyAndOrderFront(self)
		return true
	}
	
	override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		switch(menuItem.action) {
			case (#selector(MacAppDelegate.showBookmarkWindow(_:)))?:
				return NSApp.mainWindow != bookmarkWindowController?.window
			default:
				return false
		}
	}
	
	func startSetup() {
		precondition(setupController == nil)
		let sboard = SwinjectStoryboard.create(name: "Main", bundle: nil)
		let wc = sboard.instantiateWindowController()
		setupController = wc.contentViewController as? ServerSetupController
		wc.window?.makeKeyAndOrderFront(self)
		guard dockerManager!.pullIsNecessary() else {
			self.showBookmarkWindow(self)
			return
		}
		guard let future = dockerManager?.pullImages(handler: { p in
			self.setupController!.pullProgress = p
		}) else { fatalError("failed to start image pull") }
		future.onSuccess {_ in 
			wc.window?.orderOut(self)
			wc.close()
			self.showBookmarkWindow(self)
		}.onFailure { err in
			os_log("error pulling images: %{public}s", type:.error, err)
			wc.window?.orderOut(self)
			wc.close()
			self.showBookmarkWindow(self)
		}
	}
	
	func restoreSessions() {
		let defaults = UserDefaults.standard
		//load them, or create default ones
		var bookmarks = [Bookmark]()
		if let bmstr = defaults.string(forKey: PrefKeys.OpenSessions) {
			for aJsonObj in JSON.parse(bmstr).arrayValue {
				bookmarks.append(Bookmark(json: aJsonObj)!)
			}
		}
		guard let bmarkController = bookmarkWindowController?.contentViewController as? BookmarkViewController else
		{
			os_log("failed to get bookmarkViewController to restore sessions", type:.error)
			return
		}
		//TODO: show progress dialog
		for bmark in bookmarks {
			bmarkController.openSession(withBookmark: bmark, password: nil)
		}
	}
	
	func windowForAppStatus(_ session:Session?) -> NSWindow {
		return windowControllerForSession(session!)!.window!
	}
	
	@IBAction func showBookmarkWindow(_ sender:AnyObject?) {
		if nil == bookmarkWindowController {
			let container = Container()
			container.registerForStoryboard(NSWindowController.self, name: "bmarkWindow") { r,c in
				os.os_log("wc registered", type:.debug)
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
			bookmarkWindowController = sboard.instantiateController(withIdentifier: "bookmarkWindow") as? NSWindowController
			let bvc = bookmarkWindowController!.contentViewController as! BookmarkViewController
			bvc.openSessionCallback = openSession
		}
		bookmarkWindowController?.window?.makeKeyAndOrderFront(self)
	}
	
	func openSession(_ restServer:RestServer) {
		let appStatus = MacAppStatus(windowAccessor: windowForAppStatus)
		let wc = MainWindowController.createFromNib()
		sessionWindowControllers.insert(wc)
		
		let container = Container()
		container.registerForStoryboard(RootViewController.self) { r, c in
			c.appStatus = appStatus
		}
		container.registerForStoryboard(SidebarFileController.self) { r, c in
			c.appStatus = appStatus
		}
		container.registerForStoryboard(AbstractSessionViewController.self) { r, c in
			c.appStatus = appStatus
		}

		let sboard = SwinjectStoryboard.create(name: "MainController", bundle: nil, container: container)
		wc.window?.makeKeyAndOrderFront(self)
		//a bug in storyboard loading is causing DI to fail for the rootController when loaded via the window
		let root = sboard.instantiateController(withIdentifier: "rootController") as? RootViewController
		wc.contentViewController = root
		wc.appStatus = appStatus
		restServer.appStatus = appStatus
		wc.session = restServer.session
		wc.setupChildren(restServer)
	}
	
	func windowWillClose(_ note:Notification) {
		//if no windows will be visible, acitvate/show bookmark window
		if let sessionWC = (note.object as! NSWindow).windowController as? MainWindowController {
			sessionWindowControllers.remove(sessionWC)
			if sessionWindowControllers.count < 1 {
				perform(#selector(MacAppDelegate.showBookmarkWindow), with: nil, afterDelay: 0.2)
			}
		}
	}
	
	func windowControllerForSession(_ session:Session) -> MainWindowController? {
		for wc in sessionWindowControllers {
			if wc.session == session { return wc }
		}
		return nil
	}
}
