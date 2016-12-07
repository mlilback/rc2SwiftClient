//
//  MacAppDelegate.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import os
import SwinjectStoryboard
import Swinject
import Freddy
import ClientCore
import ReactiveSwift
import SwiftyUserDefaults
import DockerSupport
import Networking

// MARK: Keys for UserDefaults
extension DefaultsKeys {
	static let openSessions = DefaultsKey<JSON?>("OpenSessions")
}

@NSApplicationMain
class MacAppDelegate: NSObject, NSApplicationDelegate {
	var sessionWindowControllers = Set<MainWindowController>()
	var bookmarkWindowController: NSWindowController?
	let bookmarkManager = BookmarkManager()
	dynamic var dockerManager: DockerManager?
	var setupController: ServerSetupController?
	private var dockerWindowController: NSWindowController?
	private var appStatus: MacAppStatus?

	fileprivate dynamic var _currentProgress: Progress?
	fileprivate let _statusQueue = DispatchQueue(label: "io.rc2.statusQueue", qos: .userInitiated)

	func applicationWillFinishLaunching(_ notification: Notification) {
		dockerManager = DockerManager()
		DispatchQueue.main.async {
			self.startSetup()
		}
		let cdUrl = Bundle.main.url(forResource: "CommonDefaults", withExtension: "plist")
		UserDefaults.standard.register(defaults: NSDictionary(contentsOf: cdUrl!)! as! [String : AnyObject])
		NotificationCenter.default.addObserver(self, selector: #selector(MacAppDelegate.windowWillClose), name: NSNotification.Name.NSWindowWillClose, object: nil)
	}

	func applicationDidFinishLaunching(_ aNotification: Notification) {
		//skip startup actions if running unit tests
		guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
	#if HOCKEYAPP_ENABLED
		if ProcessInfo.processInfo.environment["DisableHockeyApp"] == nil {
			BITHockeyManager.shared().configure(withIdentifier: kHockeyAppIdentifier)
			//BITHockeyManager.sharedHockeyManager().debugLogEnabled = true
			// Do some additional configuration if needed here
			BITHockeyManager.shared().start()
		}
	#endif
		restoreSessions()
	}

	func applicationWillTerminate(_ aNotification: Notification) {
		NotificationCenter.default.removeObserver(self, name: NSNotification.Name.NSWindowWillClose, object: nil)
		let defaults = UserDefaults.standard
		//save info to restore open sessions
		var reopen = [Bookmark]()
		for controller in sessionWindowControllers {
			if let session = controller.session {
				let bmark = Bookmark(name: "irrelevant", server: session.conInfo.host, project: session.project.name, workspace: session.workspace.name)
				reopen.append(bmark)
			}
		}
		defaults[.openSessions] = reopen.toJSON()
		dockerManager = nil
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
				return true
			//for some reason this wasn't working properly as another user
//				return NSApp.mainWindow != bookmarkWindowController?.window
		case (#selector(MacAppDelegate.showDockerControl(_:)))?:
				return true
			default:
				return false
		}
	}
	
	func performPullAndPrepareContainers(_ needPull: Bool) -> SignalProducer<(), Rc2Error> {
		os_log("performPullAndPrepareContainers: %d", log: .app, type: .debug, needPull ? 1 : 0)
		guard let docker = dockerManager else { fatalError() }
		guard needPull else {
			os_log("pull not needed, preparing containers", log: .app, type: .debug)
			return docker.prepareContainers()
		}
		return docker.pullImages()
			.on( //inject side-effect to update the progress bar
				starting: {
					self.setupController?.statusMesssage = "Pulling Images…"
				}, value: { (pprogress) in
					self.setupController?.pullProgress = pprogress
			})
			.collect() // colalesce individual PullProgress values into a single array sent when pullImages is complete
			.map( { _ in } ) //map [PullProgress] to () as that is the input parameter to prepareContainers
			.flatMap(.concat) { docker.prepareContainers() }
	}
	
	/// should be only called after docker manager has initialized
	func startSetup() {
		precondition(setupController == nil)
		guard let docker = dockerManager else { fatalError("no docker manager") }
		// load window and setupController
		let sboard = SwinjectStoryboard.create(name: "Main", bundle: nil)
		let wc = sboard.instantiateWindowController()
		setupController = wc.contentViewController as? ServerSetupController
		assert(setupController != nil)
		wc.window?.makeKeyAndOrderFront(self)

		setupController!.statusMesssage = "Initializing Docker…"
		_ = docker.initialize()
			.flatMap(.concat, transform: performPullAndPrepareContainers)
			.flatMap(.concat, transform: {
				return docker.perform(operation: .start)}
			)
			.on(
				failed: { error in
					os_log("failed to start a container: %{public}s", log: .app, type: .error, error.debugDescription)
					self.appStatus?.presentError(error, session: nil)
				}, completed: {
					DispatchQueue.main.async {
						wc.window?.orderOut(nil)
						wc.close()
						self.showBookmarkWindow(nil)
					}
				}, interrupted: {
					fatalError() //should never happen
				}
			).observe(on: UIScheduler()).start()
	}
	
	func restoreSessions() {
		let defaults = UserDefaults.standard
		//load them, or create default ones
		var bookmarks: [Bookmark] = []
		if let json: JSON = defaults[.openSessions] {
			bookmarks = (try? json.decodedArray()) ?? []
		}
		let dinfo = "bwc = \(bookmarkWindowController), bmc = \(bookmarkWindowController?.contentViewController)"
		os_log("bm info: %{public}s", log: .app, type: .debug, dinfo)
		guard let bmarkController = bookmarkWindowController?.contentViewController as? BookmarkViewController else
		{
			os_log("failed to get bookmarkViewController to restore sessions", log: .app, type: .default)
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
			container.registerForStoryboard(BookmarkViewController.self) { r, c in
				c.bookmarkManager = self.bookmarkManager
			}
			container.registerForStoryboard(AddBookmarkViewController.self) { r, c in
				c.bookmarkManager = self.bookmarkManager
			}
			container.registerForStoryboard(SelectServerViewController.self) { r, c in
				c.bookmarkManager = self.bookmarkManager
			}

			let sboard = SwinjectStoryboard.create(name: "BookmarkManager", bundle: nil, container: container)
			bookmarkWindowController = sboard.instantiateController(withIdentifier: "bookmarkWindow") as? NSWindowController
			let bvc = bookmarkWindowController!.contentViewController as! BookmarkViewController
			bvc.openSessionCallback = openSession
		}
		bookmarkWindowController?.window?.makeKeyAndOrderFront(self)
	}
	
	func openSession(_ session: Session) {
		if nil == appStatus {
			appStatus = MacAppStatus(windowAccessor: windowForAppStatus)
		}
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
		//a bug in storyboard loading is causing DI to fail for the rootController when loaded via the window
		let root = sboard.instantiateController(withIdentifier: "rootController") as? RootViewController
		wc.contentViewController = root
		//we had to set the content before making visible, and have to set variables after visible
		wc.window?.makeKeyAndOrderFront(self)
		wc.appStatus = appStatus
		wc.session = session
		wc.setupChildren()
	}
	
	@IBAction func showDockerControl(_ sender:Any?) {
		if nil == dockerWindowController {
			let container = Container()
			container.registerForStoryboard(DockerViewController.self) { (r, c) in
				c.manager = self.dockerManager
			}
			let sboard = SwinjectStoryboard.create(name: "DockerControl", bundle: nil, container: container)
			dockerWindowController = sboard.instantiateWindowController()
		}
		dockerWindowController?.window?.makeKeyAndOrderFront(self)
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
			if wc.session === session { return wc }
		}
		return nil
	}
}
