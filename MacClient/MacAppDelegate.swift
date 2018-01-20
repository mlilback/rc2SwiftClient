//
//  MacAppDelegate.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import Freddy
import ClientCore
import ReactiveSwift
import SwiftyUserDefaults
import Docker
import Networking
import SBInjector
import Model
import os
import MJLLogger

// swiftlint:disable file_length

/// incremented when data in ~/Library needs to be cleared (such has when the format has changed)
let currentSupportDataVersion: Int = 2

fileprivate struct Actions {
	static let showPreferences = #selector(MacAppDelegate.showPreferencesWindow(_:))
	static let showBookmarks = #selector(MacAppDelegate.showBookmarkWindow(_:))
	static let showDockerControls = #selector(MacAppDelegate.showDockerControl(_:))
	static let newWorkspace = #selector(MacAppDelegate.newWorkspace(_:))
	static let showWorkspace = #selector(MacAppDelegate.showWorkspace(_:))
	static let backupDatabase = #selector(MacAppDelegate.backupDatabase(_:))
	static let showLog = #selector(MacAppDelegate.showLogWindow(_:))
	static let resetLogs = #selector(MacAppDelegate.resetLogs(_:))
}

extension NSStoryboard.Name {
	static let mainBoard = NSStoryboard.Name(rawValue: "Main")
	static let mainController = NSStoryboard.Name(rawValue: "MainController")
}

private extension DefaultsKeys {
	static let supportDataVersion = DefaultsKey<Int>("currentSupportDataVersion")
}

@NSApplicationMain
class MacAppDelegate: NSObject, NSApplicationDelegate {
	// MARK: - properties
	let logger = AppLogger()
	var mainStoryboard: NSStoryboard!
	var sessionWindowControllers = Set<MainWindowController>()
	var bookmarkWindowController: NSWindowController?
	let bookmarkManager = BookmarkManager()
	private var dockerEnabled = true
	@objc dynamic var dockerManager: DockerManager?
	private var backupManager: DockerBackupManager?
	var startupWindowController: StartupWindowController?
	var startupController: StartupController?
	private var onboardingController: OnboardingWindowController?
	private var dockerWindowController: NSWindowController?
	private var preferencesWindowController: NSWindowController?
	private var appStatus: MacAppStatus?
	@IBOutlet weak var workspaceMenu: NSMenu!
	private let connectionManager = ConnectionManager()
	private var dockMenu: NSMenu?
	private var dockOpenMenu: NSMenu?
	@IBOutlet weak var logLevelMenuSeperator: NSMenuItem?
	private var sessionsBeingRestored: [WorkspaceIdentifier: (NSWindow?, Error?) -> Void] = [:]
	private var workspacesBeingOpened = Set<WorkspaceIdentifier>()

	fileprivate let _statusQueue = DispatchQueue(label: "io.rc2.statusQueue", qos: .userInitiated)

	// MARK: - NSApplicationDelegate
	func applicationWillFinishLaunching(_ notification: Notification) {
		#if HOCKEYAPP_ENABLED
			if ProcessInfo.processInfo.environment["DisableHockeyApp"] == nil {
				BITHockeyManager.shared().configure(withIdentifier: kHockeyAppIdentifier)
				//BITHockeyManager.sharedHockeyManager().debugLogEnabled = true
				// Do some additional configuration if needed here
				BITHockeyManager.shared().delegate = self
				BITHockeyManager.shared().start()
			}
		#endif
		logger.start()
		logger.installLoggingUI(addMenusAfter: logLevelMenuSeperator)
		resetOutdatedCaches()
		mainStoryboard = NSStoryboard(name: .mainBoard, bundle: nil)
		precondition(mainStoryboard != nil)
		//only init dockerManager if not running unit tests or not expressly disabled
		dockerEnabled = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil && !ProcessInfo.processInfo.arguments.contains("--disableDocker")
		if dockerEnabled {
			let dm = DockerManager()
			dockerManager = dm
			backupManager = DockerBackupManager(manager: dm)
		}
		
		DispatchQueue.global().async {
			HelpController.shared.verifyDocumentationInstallation()
		}
		
		let cdUrl = Bundle(for: type(of: self)).url(forResource: "CommonDefaults", withExtension: "plist")
		// swiftlint:disable:next force_cast (swift value types don't support dictionaries from files)
		UserDefaults.standard.register(defaults: NSDictionary(contentsOf: cdUrl!)! as! [String : AnyObject])
		
		NotificationCenter.default.addObserver(self, selector: #selector(MacAppDelegate.windowWillClose(_:)), name: NSWindow.willCloseNotification, object: nil)
		
		DispatchQueue.main.async {
			self.beginStartup()
		}
	}

	func applicationDidFinishLaunching(_ aNotification: Notification) {
		//skip startup actions if running unit tests
		guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
	}

	func applicationWillTerminate(_ aNotification: Notification) {
		NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: nil)
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
		if startupWindowController?.window?.isVisible ?? false { return false } //disable menu items while docker is loading
		switch action  {
		case Actions.backupDatabase:
			return true
		case Actions.showBookmarks:
			return true
		case Actions.newWorkspace:
			return true
		case Actions.showDockerControls:
			return true
		case Actions.resetLogs:
			return true
		case Actions.showPreferences:
			return !(preferencesWindowController?.window?.isMainWindow ?? false)
		case Actions.showWorkspace:
			guard let wspaceIdent = menuItem.representedObject as? WorkspaceIdentifier else { return false }
			return windowController(for: wspaceIdent)?.window?.isMainWindow ?? true
		case Actions.showLog:
			return true
		default:
			return false
		}
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
	func window(for session: Session?) -> NSWindow? {
		//TODO: make return value optional and remove force casts
		if let window = windowControllerForSession(session!)?.window {
			return window
		}
		return nil
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
		
		let sboard = NSStoryboard(name: NSStoryboard.Name(rawValue: "MainController"), bundle: nil)
		sboard.injectionContext = icontext
		//a bug in storyboard loading is causing DI to fail for the rootController when loaded via the window
		let root = sboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier(rawValue: "rootController")) as? RootViewController
		wc.contentViewController = root
		wc.window?.identifier = NSUserInterfaceItemIdentifier(rawValue: "session")
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
			Log.warn("already opening \(ident)", .app)
			return
		}
		guard let conInfo = connectionManager.localConnection,
			let optWspace = try? conInfo.project(withId: ident.projectId).workspace(withId: ident.wspaceId),
			let wspace = optWspace
		else {
			Log.warn("failed to find workspace \(ident) that we're supposed to open", .app)
			return
		}
		workspacesBeingOpened.insert(ident)
		let session = Session(connectionInfo: conInfo, workspace: wspace)
		session.open().observe(on: UIScheduler()).take(during: session.lifetime).start
		{ [weak self] event in
			switch event {
			case .completed:
				DispatchQueue.main.async {
					self?.openSessionWindow(session)
				}
			case .failed(let err):
				Log.error("failed to open websocket \(err)", .session)
				fatalError()
			case .value: //(let _):
				// do nothing as using indeterminate progress
				break
			case .interrupted:
				break //should never happen
			}
		}
	}
}

// MARK: - menus
extension MacAppDelegate: NSMenuDelegate {
	func menuWillOpen(_ menu: NSMenu) {
		guard menu == workspaceMenu else { return }
		updateOpen(menu: menu)
	}

	/// Adds menu items for workspaces in project
	///
	/// - Parameters:
	///   - menu: menu to add workspaces to
	///   - project: project whose workspaces will be added to menu
	private func update(menu: NSMenu, for project: AppProject) {
		menu.title = project.name
		menu.removeAllItems()
		for aWorkspace in project.workspaces.value.sorted(by: { $0.name < $1.name }) {
			let wspaceItem = NSMenuItem(title: aWorkspace.name, action: Actions.showWorkspace, keyEquivalent: "")
			wspaceItem.representedObject = aWorkspace.identifier
			wspaceItem.tag = aWorkspace.wspaceId
			menu.addItem(wspaceItem)
		}
	}

	/// Sets menu's items to either be all workspaces in project (if only 1), or submenu items for each project containing its workspaces
	///
	/// - Parameter menu: menu to update
	fileprivate func updateOpen(menu: NSMenu) {
		menu.removeAllItems()
		guard let projects = connectionManager.localConnection?.projects.value, projects.count > 0 else {
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
}

// MARK: - actions
extension MacAppDelegate {
	@IBAction func resetLogs(_ sender: Any?) {
		logger.resetLogs()
	}
	
	@IBAction func newWorkspace(_ sender: Any?) {
		guard let conInfo = connectionManager.localConnection, let project = conInfo.defaultProject else { fatalError() }
		DispatchQueue.main.async {
			let existingNames = project.workspaces.value.map { $0.name.lowercased() }
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
			let sboard = NSStoryboard(name: NSStoryboard.Name(rawValue: "Preferences"), bundle: nil)
			preferencesWindowController = sboard.instantiateInitialController() as? NSWindowController
			preferencesWindowController?.window?.setFrameAutosaveName(NSWindow.FrameAutosaveName(rawValue: "PrefsWindow"))
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
	
	@IBAction func backupDatabase(_ sender: Any?) {
		backupManager?.performBackup().start()
	}
	
	@IBAction func showDockerControl(_ sender: Any?) {
		if dockerManager == nil { Log.info("docker disabled", .app); return }
		if nil == dockerWindowController {
			let icontext = InjectorContext()
			icontext.register(DockerTabViewController.self) { controller in
				controller.manager = self.dockerManager
			}
			icontext.register(DockerManagerInjectable.self) { controller in
				controller.manager = self.dockerManager
			}
			icontext.register(DockerBackupViewController.self) { controller in
				controller.backupManager = self.backupManager
			}
			let sboard = NSStoryboard(name: NSStoryboard.Name(rawValue: "DockerControl"), bundle: nil)
			sboard.injectionContext = icontext
			dockerWindowController = sboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("DockerWindowController")) as? NSWindowController
		}
		dockerWindowController?.window?.makeKeyAndOrderFront(self)
	}
	
	@IBAction func showLogWindow(_ sender: Any?) {
		logger.showLogWindow(sender)
	}
	
	@IBAction func adjustGlobalLogLevel(_ sender: Any?) {
		logger.adjustGlobalLogLevel(sender)
	}
	
	@objc func windowWillClose(_ note: Notification) {
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
		for wc in sessionWindowControllers where wc.session === session {
			return wc
		}
		return nil
	}
}

// MARK: - restoration
extension MacAppDelegate: NSWindowRestoration {
	class func restoreWindow(withIdentifier identifier: NSUserInterfaceItemIdentifier, state: NSCoder, completionHandler: @escaping (NSWindow?, Error?) -> Void)
	{
		guard identifier.rawValue == "session",
			let me = NSApp.delegate as? MacAppDelegate,
			let bmarkData = state.decodeObject(forKey: "bookmark") as? Data,
			let bmark: Bookmark = try? JSONDecoder().decode(Bookmark.self, from: bmarkData)
		else {
			completionHandler(nil, Rc2Error(type: .unknown, nested: nil, explanation: "Unsupported window identifier"))
			return
		}
		completionHandler(nil, nil)
		me.sessionsBeingRestored[bmark.workspaceIdent] = completionHandler
	}
}

// MARK: - private
extension MacAppDelegate {
	func resetOutdatedCaches() {
		let defaults = UserDefaults.standard
		let lastVersion = defaults[.supportDataVersion]
		let forceReset = ProcessInfo.processInfo.arguments.contains("--resetSupportData")
		guard lastVersion < currentSupportDataVersion,
			!forceReset
			else { return }
		// need to remove files from ~/Library
		defer {
			defaults[.supportDataVersion] = currentSupportDataVersion
		}
		let fm = FileManager()
		if let cacheDir = (try? fm.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false).appendingPathComponent(AppInfo.bundleIdentifier, isDirectory: true))
		{
			Log.info("removing \(cacheDir.path)", .app)
			try? fm.removeItem(at: cacheDir)
		}
		if let supportDir = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false).appendingPathComponent(AppInfo.bundleIdentifier, isDirectory: true)
		{
			Log.info("removing \(supportDir.path)", .app)
			try? fm.removeItem(at: supportDir)
		}
	}
}

// MARK: - HockeyApp

extension MacAppDelegate: BITHockeyManagerDelegate {
	func applicationLog(for crashManager: BITCrashManager!) -> String! {
		return logger.jsonLogFromLastLaunch()
	}
}

// MARK: - startup
extension MacAppDelegate {
	/// load the setup window and start setup process
	fileprivate func beginStartup() {
		precondition(startupController == nil)
		if dockerEnabled {
			precondition(dockerManager != nil)
		}
		
		// load window and setupController.
		startupWindowController = mainStoryboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier(rawValue: "StartupWindowController")) as? StartupWindowController
		guard let wc = startupWindowController else { fatalError("failed to load startup window controller") }
		startupController = startupWindowController!.contentViewController as? StartupController
		assert(startupController != nil)
		wc.window?.makeKeyAndOrderFront(self)
		assert(wc.window!.isVisible)
		assert(wc.contentViewController?.view.window == wc.window)
		
		//skip docker stage if performing unit tests
		if !dockerEnabled {
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
		case .downloading:
			break //changes handled via observing pull signal
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
	
	private func handleStartupError(_ error: Rc2Error) {
		onboardingController?.window?.orderOut(nil)
		let alert = NSAlert()
		alert.messageText = "Error starting application"
		alert .informativeText = error.nestedDescription ?? error.localizedDescription
		alert.addButton(withTitle: "Quit")
		alert.runModal()
		NSApp.terminate(self)
	}
	
	private func handleLoginError(_ error: Rc2Error) {
		guard let nestederror = error.nestedError as? NetworkingError,
			case NetworkingError.invalidHttpStatusCode(let rsp) = nestederror
		else { handleStartupError(error); return }
		switch rsp.statusCode {
		case 401: // unauthorized, login failed
			// TODO: provide better error notification
			Log.warn("login unauthorized", .app)
			handleStartupError(error)
		default:
			handleStartupError(error)
		}
	}
	
	private func startupLocalLogin() {
		let loginFactory = LoginFactory()
		let host = ServerHost.localHost
		let pass = NetworkConstants.localServerPassword
		loginFactory.login(to: host, as: host.user, password: pass).observe(on: UIScheduler()).startWithResult { (result) in
			guard let conInfo = result.value else {
				self.handleLoginError(result.error!)
				return
			}
			self.connectionManager.localConnection = conInfo
			self.advanceStartupStage()
		}
	}
	
	fileprivate func showOnboarding() {
		if nil == onboardingController {
			// swiftlint:disable:next force_cast
			onboardingController = (mainStoryboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier(rawValue: "OnboardingWindowController")) as! OnboardingWindowController)
			onboardingController?.viewController.conInfo = connectionManager.localConnection
			onboardingController?.viewController.openLocalWorkspace = openLocalSession
		}
		onboardingController!.window?.makeKeyAndOrderFront(self)
	}
	
	/// should be only called after docker manager has initialized
	private  func startupDocker() {
		guard let docker = dockerManager else { fatalError() }
		
		_ = docker.initialize()
			.flatMap(.concat, performPullAndPrepareContainers)
			.flatMap(.concat, { _ in
				return docker.perform(operation: .start)
			})
			//really want to act when complete, but have to map, so we collect all values and pass on a single value
			.collect().map({ _ in return () })
			.flatMap(.concat, { _ in return docker.waitUntilRunning() })
			.flatMap(.concat, { _ in return docker.waitUntilDBRunning() })
			.observe(on: UIScheduler())
			.startWithResult { [weak self] result in
				guard result.error == nil else {
					Log.error("failed to start docker: \(result.error?.description ?? "-"), \(result.error?.nestedDescription ?? "0")", .app)
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
		Log.debug("pulling: \(needPull)", .app)
		guard let docker = dockerManager else { fatalError() }
		guard needPull else {
			Log.debug("pull not needed, preparing containers", .app)
			return docker.prepareContainers()
		}
		return docker.pullImages()
			.observe(on: UIScheduler())
			.on( //inject side-effect to update the progress bar
				starting: {
					self.startupController?.updateStatus(message: "Pulling Images…")
					self.startupController?.stage = .downloading
			}, completed: {
				self.startupController?.stage = .docker
			}, value: { (pprogress) in
				self.startupController?.pullProgress = pprogress
			})
			.collect() // coalesce individual PullProgress values into a single array sent when pullImages is complete
			.mapError({ (derror) -> Rc2Error in
				let err = Rc2Error(type: .docker, nested: derror)
				return err
			})
			.map( { (_) -> Void in }) //map [PullProgress] to () as that is the input parameter to prepareContainers
			.flatMap(.concat) { _ in docker.prepareContainers() }
	}
}

//extension MacAppDelegate: BITCrashManagerDelegate {
//	func attachment(for crashManager: BITCrashManager!) -> BITHockeyAttachment! {
//
//	}
//
//}
