//
//  MacAppDelegate.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import os
import Freddy
import ClientCore
import ReactiveSwift
import SwiftyUserDefaults
import DockerSupport
import Networking
import SBInjector

// swiftlint:disable file_length

fileprivate struct Actions {
	static let showPreferences = #selector(MacAppDelegate.showPreferencesWindow(_:))
	static let showBookmarks = #selector(MacAppDelegate.showBookmarkWindow(_:))
	static let showDockerControls = #selector(MacAppDelegate.showDockerControl(_:))
	static let newWorkspace = #selector(MacAppDelegate.newWorkspace(_:))
	static let showWorkspace = #selector(MacAppDelegate.showWorkspace(_:))
}

@NSApplicationMain
class MacAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
	// MARK: - properties
	var mainStoryboard: NSStoryboard!
	var sessionWindowControllers = Set<MainWindowController>()
	var bookmarkWindowController: NSWindowController?
	let bookmarkManager = BookmarkManager()
	dynamic var dockerManager: DockerManager?
	var startupWindowController: StartupWindowController?
	var startupController: StartupController?
	fileprivate var onboardingController: OnboardingWindowController?
	fileprivate var dockerWindowController: NSWindowController?
	fileprivate var preferencesWindowController: NSWindowController?
	fileprivate var appStatus: MacAppStatus?
	@IBOutlet weak var workspaceMenu: NSMenu!
	fileprivate let connectionManager = ConnectionManager()
	fileprivate var dockMenu: NSMenu?
	fileprivate var dockOpenMenu: NSMenu?
	fileprivate var sessionsBeingRestored: [WorkspaceIdentifier: (NSWindow?, Error?) -> Void] = [:]
	fileprivate var workspacesBeingOpened = Set<WorkspaceIdentifier>()

	fileprivate let _statusQueue = DispatchQueue(label: "io.rc2.statusQueue", qos: .userInitiated)

	// MARK: - NSApplicationDelegate
	func applicationWillFinishLaunching(_ notification: Notification) {
		#if HOCKEYAPP_ENABLED
			if ProcessInfo.processInfo.environment["DisableHockeyApp"] == nil {
				BITHockeyManager.shared().configure(withIdentifier: kHockeyAppIdentifier)
				//BITHockeyManager.sharedHockeyManager().debugLogEnabled = true
				// Do some additional configuration if needed here
				BITHockeyManager.shared().start()
			}
		#endif
		mainStoryboard = NSStoryboard(name: "Main", bundle: nil)
		precondition(mainStoryboard != nil)
		//only init dockerManager if not running unit tests
		if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
			dockerManager = DockerManager()
		}
		
		DispatchQueue.global().async {
			HelpController.shared.verifyDocumentationInstallation()
		}
		
		let cdUrl = Bundle(for: type(of: self)).url(forResource: "CommonDefaults", withExtension: "plist")
		// swiftlint:disable:next force_cast (swift value types don't support dictionaries from files)
		UserDefaults.standard.register(defaults: NSDictionary(contentsOf: cdUrl!)! as! [String : AnyObject])
		
		NotificationCenter.default.addObserver(self, selector: #selector(MacAppDelegate.windowWillClose), name: .NSWindowWillClose, object: nil)
		
		DispatchQueue.main.async {
			self.beginStartup()
		}
	}

	func applicationDidFinishLaunching(_ aNotification: Notification) {
		//skip startup actions if running unit tests
		guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
	}

	func applicationWillTerminate(_ aNotification: Notification) {
		NotificationCenter.default.removeObserver(self, name: NSNotification.Name.NSWindowWillClose, object: nil)
		dockerManager = nil
	}

	func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
		return NSApp.modalWindow == nil
	}
	
	func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
		//bookmarkWindowController?.window?.makeKeyAndOrderFront(self)
		onboardingController?.window?.makeKeyAndOrderFront(self)
		return true
	}
	
	func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
		if nil == dockMenu {
			dockMenu = NSMenu(title: "Dock")
			dockOpenMenu = NSMenu(title: "Open")
			let openMI = NSMenuItem(title: "Open", action: nil, keyEquivalent: "")
			openMI.submenu = dockOpenMenu
			dockMenu?.addItem(openMI)
			updateOpen(menu: dockOpenMenu!)
		}
		return dockMenu
	}
}

// MARK: - basic functionality
extension MacAppDelegate {
	override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		guard let action = menuItem.action else { return false }
		switch action  {
			case Actions.showBookmarks:
				return true
		case Actions.newWorkspace:
			return true
		case Actions.showDockerControls:
			return true
		case Actions.showPreferences:
			return !(preferencesWindowController?.window?.isMainWindow ?? false)
		case Actions.showWorkspace:
			guard let wspaceIdent = menuItem.representedObject as? WorkspaceIdentifier else { return false }
			return windowController(for: wspaceIdent)?.window?.isMainWindow ?? true
		default:
			return false
		}
	}
	
	func menuWillOpen(_ menu: NSMenu) {
		guard menu == workspaceMenu else { return }
		updateOpen(menu: menu)
	}
	
	/// returns the session associated with window if it is a session window
	func session(for window: NSWindow?) -> Session? {
		guard let wc = NSApp.mainWindow?.windowController as? MainWindowController else { return nil }
		return wc.session
	}

	/// returns the window controller for the identified workspace
	func windowController(for workspaceIdent: WorkspaceIdentifier) -> MainWindowController? {
		return sessionWindowControllers.first(where: { $0.session?.workspace.wspaceId == workspaceIdent.wspaceId })
	}
	
	/// returns the window for the specified session
	func window(for session: Session?) -> NSWindow {
		//TODO: make return value optional and remove force casts
		return windowControllerForSession(session!)!.window!
	}
	
	func openSessionWindow(_ session: Session) {
		defer {
			workspacesBeingOpened.remove(session.workspace.identifier)
		}
		if nil == appStatus {
			appStatus = MacAppStatus(windowAccessor: window)
		}
		let wc = MainWindowController.createFromNib()
		sessionWindowControllers.insert(wc)
		
		let icontext = InjectorContext()
		icontext.register(AbstractSessionViewController.self) { controller in
			controller.appStatus = self.appStatus
		}
		
		let sboard = NSStoryboard(name: "MainController", bundle: nil)
		sboard.injectionContext = icontext
		//a bug in storyboard loading is causing DI to fail for the rootController when loaded via the window
		let root = sboard.instantiateController(withIdentifier: "rootController") as? RootViewController
		wc.contentViewController = root
		wc.window?.identifier = "session"
		wc.window?.restorationClass = type(of: self)
		//we had to set the content before making visible, and have to set variables after visible
		wc.window?.makeKeyAndOrderFront(self)
		wc.appStatus = appStatus
		wc.session = session
		wc.setupChildren()
		if let _ = sessionsBeingRestored.removeValue(forKey: session.workspace.identifier) {
			//callback(wc.window, nil)
			if sessionsBeingRestored.count < 1 {
				advanceStartupStage()
			}
		}
		if onboardingController?.window?.isVisible ?? false {
			onboardingController?.window?.orderOut(self)
		}
	}
	
	func openLocalSession(for wspaceIdentifier: WorkspaceIdentifier?) {
		guard let ident = wspaceIdentifier else {
			newWorkspace(self)
			return
		}
		guard !workspacesBeingOpened.contains(ident) else {
			os_log("already opening %{public}s", log: .app, ident.description)
			return
		}
		guard let conInfo = connectionManager.localConnection, let wspace = conInfo.project(withId: ident.projectId)?.workspace(withId: ident.wspaceId) else
		{
			os_log("failed to find workspace %d that we're suppoesd to open", log: .app)
			return
		}
		workspacesBeingOpened.insert(ident)
		let session = Session(connectionInfo: conInfo, workspace: wspace)
		session.open().observe(on: UIScheduler()).on(starting: {
		}, terminated: {
		}).start { [weak self] event in
			switch event {
			case .completed:
				self?.openSessionWindow(session)
			case .failed(let err):
				os_log("failed to open websocket: %{public}s", log: .session, err.localizedDescription)
				fatalError()
			case .value: //(let _):
				// do nothing as using indeterminate progress
				break
			case .interrupted:
				break //should never happen
			}
		}
	}
	
	/// Sets menu's items to either be all workspaces in project (if only 1), or submenu items for each project containing its workspaces
	///
	/// - Parameter menu: menu to update
	fileprivate func updateOpen(menu: NSMenu) {
		menu.removeAllItems()
		guard let projects = connectionManager.localConnection?.projects, projects.count > 0 else {
			return
		}
		guard projects.count > 1 else {
			update(menu: menu, for: projects.first!)
			return
		}
		for aProject in projects {
			let pmenu = NSMenu(title: aProject.name)
			update(menu: pmenu, for: aProject)
			let pmi = NSMenuItem(title: aProject.name, action: nil, keyEquivalent: "")
			menu.addItem(pmi)
		}
	}
	
	/// Adds menu items for workspaces in project
	///
	/// - Parameters:
	///   - menu: menu to add workspaces to
	///   - project: project whose workspaces will be added to menu
	fileprivate func update(menu: NSMenu, for project: Project) {
		menu.title = project.name
		menu.removeAllItems()
		for aWorkspace in project.workspaces.sorted(by: { $0.name < $1.name }) {
			let wspaceItem = NSMenuItem(title: aWorkspace.name, action: Actions.showWorkspace, keyEquivalent: "")
			wspaceItem.representedObject = WorkspaceIdentifier(aWorkspace)
			wspaceItem.tag = aWorkspace.wspaceId
			menu.addItem(wspaceItem)
		}
	}
}

// MARK: - actions
extension MacAppDelegate {
	@IBAction func newWorkspace(_ sender: Any) {
		guard let conInfo = connectionManager.localConnection, let project = conInfo.defaultProject else { fatalError() }
		DispatchQueue.main.async {
			let existingNames = project.workspaces.map { $0.name.lowercased() }
			let prompter = InputPrompter(prompt: "Workspace name:", defaultValue: "new workspace")
			prompter.validator = { proposedName in
				return !existingNames.contains(proposedName.lowercased())
			}
			prompter.prompt(window: nil) { success, _ in
				guard success else { return }
				let client = Rc2RestClient(conInfo)
				client.create(workspace: prompter.stringValue, project: conInfo.defaultProject!)
					.observe(on: UIScheduler())
					.startWithFailed { error in
						//this should never happen unless serious server error
						//TODO: this does not actually present an error
						self.appStatus?.presentError(error, session: nil)
					}
			}
		}
	}
	
	@IBAction func showWorkspace(_ sender: Any?) {
		guard let menuItem = sender as? NSMenuItem, let ident = menuItem.representedObject as? WorkspaceIdentifier else { return }
		if let wc = windowController(for: ident) { wc.window?.makeKeyAndOrderFront(self); return }
		openLocalSession(for: ident)
	}
	
	@IBAction func showPreferencesWindow(_ sender: AnyObject?) {
		if nil == preferencesWindowController {
			let sboard = NSStoryboard(name: "Preferences", bundle: nil)
			preferencesWindowController = sboard.instantiateInitialController() as? NSWindowController
			preferencesWindowController?.window?.setFrameAutosaveName("PrefsWindow")
		}
		preferencesWindowController?.showWindow(self)
	}
	
	@IBAction func showBookmarkWindow(_ sender: AnyObject?) {
		showOnboarding()
//		onboardingController?.window?.makeKeyAndOrderFront(self)
//		if nil == bookmarkWindowController {
//			let container = Container()
//			container.registerForStoryboard(BookmarkViewController.self) { r, c in
//				c.bookmarkManager = self.bookmarkManager
//			}
//			container.registerForStoryboard(AddBookmarkViewController.self) { r, c in
//				c.bookmarkManager = self.bookmarkManager
//			}
//			container.registerForStoryboard(SelectServerViewController.self) { r, c in
//				c.bookmarkManager = self.bookmarkManager
//			}
//
//			let sboard = SwinjectStoryboard.create(name: "BookmarkManager", bundle: nil, container: container)
//			bookmarkWindowController = sboard.instantiateController(withIdentifier: "bookmarkWindow") as? NSWindowController
//			let bvc = bookmarkWindowController!.contentViewController as! BookmarkViewController
//			bvc.openSessionCallback = openSessionWindow
//		}
//		bookmarkWindowController?.window?.makeKeyAndOrderFront(self)
	}
	
	@IBAction func showDockerControl(_ sender:Any?) {
		if nil == dockerWindowController {
			let icontext = InjectorContext()
			icontext.register(DockerViewController.self) { controller in
				controller.manager = self.dockerManager
			}
			let sboard = NSStoryboard(name: "DockerControl", bundle: nil)
			sboard.injectionContext = icontext
			dockerWindowController = sboard.instantiateWindowController()
		}
		dockerWindowController?.window?.makeKeyAndOrderFront(self)
	}
	
	func windowWillClose(_ note: Notification) {
		//if no windows will be visible, acitvate/show bookmark window
		if let window = note.object as? NSWindow,
			let sessionWC = window.windowController as? MainWindowController
		{
			sessionWindowControllers.remove(sessionWC)
			if sessionWindowControllers.count < 1 {
				perform(Actions.showBookmarks, with: nil, afterDelay: 0.2)
			}
		}
	}
	
	func windowControllerForSession(_ session: Session) -> MainWindowController? {
		for wc in sessionWindowControllers {
			if wc.session === session { return wc }
		}
		return nil
	}
}

// MARK: - restoration
extension MacAppDelegate: NSWindowRestoration {
	class func restoreWindow(withIdentifier identifier: String, state: NSCoder, completionHandler: @escaping (NSWindow?, Error?) -> Void)
	{
		guard identifier == "session",
			let me = NSApp.delegate as? MacAppDelegate,
			let bmarkData = state.decodeObject(forKey: "bookmark") as? Data,
			let bmark = try? Bookmark(json: JSON(data: bmarkData)) else
		{
			completionHandler(nil, Rc2Error(type: .unknown, nested: nil, explanation: "Unsupported window identifier"))
			return
		}
		completionHandler(nil, nil)
		me.sessionsBeingRestored[bmark.workspaceIdent] = completionHandler
	}
}

// MARK: - startup
extension MacAppDelegate {
	/// load the setup window and start setup process
	fileprivate func beginStartup() {
		precondition(startupController == nil)
		precondition(dockerManager != nil)
		
		// load window and setupController.
		startupWindowController = mainStoryboard.instantiateController(withIdentifier: "StartupWindowController") as? StartupWindowController
		guard let wc = startupWindowController else { fatalError("failed to load startup window controller") }
		startupController = startupWindowController!.contentViewController as? StartupController
		assert(startupController != nil)
		wc.window?.makeKeyAndOrderFront(self)
		assert(wc.window!.isVisible)
		assert(wc.contentViewController?.view.window == wc.window)
		
		//skip docker stage if performing unit tests
		if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
			startupController!.stage = .docker
		}
		//move to the next stage
		advanceStartupStage()
	}
	
	//advances to the next startup stage
	fileprivate func advanceStartupStage() {
		guard let setupWC = startupWindowController else { fatalError("advanceStartupStage() called without a setup controller") }
		switch startupController!.stage {
		case .initial:
			startupDocker()
			startupController!.stage = .docker
		case .docker:
			startupController!.stage = .localLogin
			startupLocalLogin()
		case .localLogin:
			startupController!.stage = .restoreSessions
			restoreSessions()
		case .restoreSessions:
			startupController!.stage = .complete
			setupWC.window?.orderOut(nil)
			setupWC.close()
			startupController = nil
			startupWindowController = nil
			dockMenu = nil
			if sessionWindowControllers.count < 1 {
				showOnboarding()
			} else {
				NSApp.mainWindow?.makeKeyAndOrderFront(self)
			}
		case .complete:
			fatalError("should never reach this point")
		}
	}
	
	private func handleStartupError(_ error: Error) {
		let alert = NSAlert()
		alert.messageText = "Error starting application"
		alert .informativeText = error.localizedDescription
		alert.addButton(withTitle: "Quit")
		alert.runModal()
		NSApp.terminate(self)
	}
	
	private func startupLocalLogin() {
		let loginFactory = LoginFactory()
		let host = ServerHost.localHost
		let pass = NetworkConstants.localServerPassword
		loginFactory.login(to: host, as: host.user, password: pass).observe(on: UIScheduler()).startWithResult { (result) in
			guard let conInfo = result.value else {
				self.handleStartupError(result.error!)
				return
			}
			self.connectionManager.localConnection = conInfo
			self.advanceStartupStage()
		}
	}
	
	fileprivate func showOnboarding() {
		if nil == onboardingController {
			// swiftlint:disable:next force_cast
			onboardingController = (mainStoryboard.instantiateController(withIdentifier: "OnboardingWindowController") as! OnboardingWindowController)
			onboardingController?.viewController.conInfo = connectionManager.localConnection
			onboardingController?.viewController.openLocalWorkspace = openLocalSession
		}
		onboardingController!.window?.makeKeyAndOrderFront(self)
	}
	
	/// should be only called after docker manager has initialized
	private  func startupDocker() {
		guard let docker = dockerManager else { fatalError() }
		
		_ = docker.initialize()
			.flatMap(.concat, transform: performPullAndPrepareContainers)
			.flatMap(.concat, transform: {
				return docker.perform(operation: .start)
			})
			//really want to act when complete, but have to map, so we collect all values and pass on a single value
			.collect().map({ _ in return () })
			.flatMap(.concat, transform: { return docker.waitUntilRunning() })
			.observe(on: UIScheduler())
			.startWithResult { [weak self] result in
				guard result.error == nil else {
					os_log("failed to start docker: %{public}s", log: .app, type: .error, result.error!.debugDescription)
					self!.appStatus?.presentError(result.error!, session: nil)
					self!.handleStartupError(result.error!) //should never return
					return
				}
				self!.advanceStartupStage()
			}
	}
	
	private func restoreSessions() {
		guard sessionsBeingRestored.count > 0 else { advanceStartupStage(); return }
		for ident in self.sessionsBeingRestored.keys {
			openLocalSession(for: ident)
		}
		//TODO: use startupController for progress, perform async
	}

	private func performPullAndPrepareContainers(_ needPull: Bool) -> SignalProducer<(), Rc2Error> {
		os_log("performPullAndPrepareContainers: %d", log: .app, type: .debug, needPull ? 1 : 0)
		guard let docker = dockerManager else { fatalError() }
		guard needPull else {
			os_log("pull not needed, preparing containers", log: .app, type: .debug)
			return docker.prepareContainers()
		}
		return docker.pullImages()
			.on( //inject side-effect to update the progress bar
				starting: {
					self.startupController?.statusMesssage = "Pulling Images…"
			}, value: { (pprogress) in
				self.startupController?.pullProgress = pprogress
			})
			.collect() // colalesce individual PullProgress values into a single array sent when pullImages is complete
			.map( { _ in }) //map [PullProgress] to () as that is the input parameter to prepareContainers
			.flatMap(.concat) { docker.prepareContainers() }
	}
}

//extension MacAppDelegate: BITCrashManagerDelegate {
//	func attachment(for crashManager: BITCrashManager!) -> BITHockeyAttachment! {
//
//	}
//
//}
