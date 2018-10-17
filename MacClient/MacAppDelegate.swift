//
//  MacAppDelegate.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import Freddy
import Rc2Common
import ClientCore
import ReactiveSwift
import SwiftyUserDefaults
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
	static let newWorkspace = #selector(MacAppDelegate.newWorkspace(_:))
	static let showWorkspace = #selector(MacAppDelegate.showWorkspace(_:))
	static let showLog = #selector(MacAppDelegate.showLogWindow(_:))
	static let resetLogs = #selector(MacAppDelegate.resetLogs(_:))
	static let toggleCloud = #selector(MacAppDelegate.toggleCloudUsage(_:))
}

private extension DefaultsKeys {
	static let supportDataVersion = DefaultsKey<Int>("currentSupportDataVersion")
	static let connectToCloud = DefaultsKey<Bool?>("connectToCloud")
}

@NSApplicationMain
class MacAppDelegate: NSObject, NSApplicationDelegate {
	// MARK: - properties
	let logger = AppLogger()
	var mainStoryboard: NSStoryboard!
	var sessionWindowControllers = Set<MainWindowController>()
	var startupWindowController: StartupWindowController?
	var startupController: StartupController?
	var loginController: LoginViewController?
	var loginWindowController: NSWindowController?
	private var onboardingController: OnboardingWindowController?
	private var preferencesWindowController: NSWindowController?
	private var appStatus: MacAppStatus?
	@IBOutlet weak var workspaceMenu: NSMenu!
	private let connectionManager = ConnectionManager()
	private var dockMenu: NSMenu?
	private var dockOpenMenu: NSMenu?
	@IBOutlet weak var logLevelMenuSeperator: NSMenuItem?
	private var sessionsBeingRestored: [WorkspaceIdentifier: (NSWindow?, Error?) -> Void] = [:]
	private var workspacesBeingOpened = Set<WorkspaceIdentifier>()

	private lazy var templateManager: CodeTemplateManager = {
		do {
			let dataFolder = try AppInfo.subdirectory(type: .applicationSupportDirectory, named: "CodeTemplates", create: true)
			let defaultFolder = Bundle.main.resourceURL!.appendingPathComponent("CodeTemplates")
			return try CodeTemplateManager(dataFolderUrl: dataFolder, defaultFolderUrl: defaultFolder)
		} catch {
			Log.error("failed to load template manager: \(error)", .app)
			fatalError("failed to load template manager")
		}
	}()

	fileprivate let _statusQueue = DispatchQueue(label: "io.rc2.statusQueue", qos: .userInitiated)

	// MARK: - NSApplicationDelegate
	func applicationWillFinishLaunching(_ notification: Notification) {
		logger.start()
		logger.installLoggingUI(addMenusAfter: logLevelMenuSeperator)
		checkIfSupportFileResetNeeded()
		mainStoryboard = NSStoryboard(name: .mainBoard, bundle: nil)
		precondition(mainStoryboard != nil)
		
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
		case Actions.newWorkspace:
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
		case Actions.toggleCloud:
			menuItem.state = (UserDefaults.standard[.connectToCloud] ?? false) ? .on : .off
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
		icontext.register(NotebookEditorController.self) { controller in
			controller.templateManager = self.templateManager
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
	
	/// opens a session for workspace. If already open, brings that session window to the front
	func openSession(workspace: AppWorkspace) {
		// if already open, bring to front
		if let controller = windowController(for: workspace.identifier) {
			controller.window?.orderFront(self)
			return
		}
		guard let conInfo = connectionManager.currentConnection
			else { Log.warn("asked to open session without connection info"); return }
		let session = Session(connectionInfo: conInfo, workspace: workspace)
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
	
	/// convience method that looks up a workspace based on an identifier, then calls openSession(workspace:)
	func openLocalSession(for wspaceIdentifier: WorkspaceIdentifier?) {
		guard let ident = wspaceIdentifier else {
			newWorkspace(self)
			return
		}
		guard !workspacesBeingOpened.contains(ident) else {
			Log.warn("already opening \(ident)", .app)
			return
		}
		guard let conInfo = connectionManager.currentConnection,
			let wspace = conInfo.workspace(withIdentifier: ident)
		else {
			Log.warn("failed to find workspace \(ident) that we're supposed to open", .app)
			return
		}
		workspacesBeingOpened.insert(ident)
		openSession(workspace: wspace)
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
		guard let projects = connectionManager.currentConnection?.projects.value, projects.count > 0 else {
			return
		}
		guard projects.count > 1 else {
			update(menu: menu, for: projects.first!)
			return
		}
		for aProject in projects.sorted(by: { $0.name < $1.name }) {
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
	
	@IBAction func resetSupportFiles(_ sender: Any?) {
		removeSupportFiles()
	}
	
	@IBAction func newWorkspace(_ sender: Any?) {
		guard let conInfo = connectionManager.currentConnection, let project = conInfo.defaultProject else { fatalError() }
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
			let icontext = InjectorContext()
			icontext.register(TemplatesPrefsController.self) { controller in
				controller.templateManager = self.templateManager
			}
			
			let sboard = NSStoryboard(name: .prefs, bundle: nil)
			sboard.injectionContext = icontext
			preferencesWindowController = sboard.instantiateInitialController() as? NSWindowController
			preferencesWindowController?.window?.setFrameAutosaveName(NSWindow.FrameAutosaveName(rawValue: "PrefsWindow"))
		}
		preferencesWindowController?.showWindow(self)
	}
	
	@IBAction func showLogWindow(_ sender: Any?) {
		logger.showLogWindow(sender)
	}
	
	@IBAction func toggleCloudUsage(_ sender: Any?) {
//		let currentValue = UserDefaults.standard[.connectToCloud] ?? false
//		UserDefaults.standard[.connectToCloud] = !currentValue
//		// relaunch application
//		let task = Process()
//		task.launchPath = "/bin/sh"
//		task.arguments = ["-c", "sleep 0.5; open \"\(Bundle.main.bundlePath)\""]
//		task.launch()
//		NSApp.terminate(nil)
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
		guard let me = NSApp.delegate as? MacAppDelegate else { fatalError("incorrect delegate??") }
		switch identifier {
		case .sessionWindow:
			guard let bmarkData = state.decodeObject(forKey: "bookmark") as? Data,
				let bmark: Bookmark = try? JSONDecoder().decode(Bookmark.self, from: bmarkData)
				else {
					completionHandler(nil, Rc2Error(type: .unknown, nested: nil, explanation: "Unsupported window identifier"))
					return
				}
			completionHandler(nil, nil)
			me.sessionsBeingRestored[bmark.workspaceIdent] = completionHandler
		case .logWindow:
			completionHandler(me.logger.logWindow(show: false), nil)
		default:
			completionHandler(nil, Rc2Error(type: .unknown, nested: nil, explanation: "Unsupported window identifier"))
		}
	}
}

// MARK: - private
extension MacAppDelegate {
	func checkIfSupportFileResetNeeded() {
		let defaults = UserDefaults.standard
		let lastVersion = defaults[.supportDataVersion]
		let forceReset = ProcessInfo.processInfo.arguments.contains("--resetSupportData")
		if lastVersion < currentSupportDataVersion || forceReset {
			removeSupportFiles()
		}
	}
	
	/// removes files from ~/Library
	private func removeSupportFiles() {
		let defaults = UserDefaults.standard
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

// MARK: - startup
extension MacAppDelegate {
	/// load the setup window and start setup process
	fileprivate func beginStartup() {
		precondition(startupController == nil)
		
		// load window and setupController.
		startupWindowController = mainStoryboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier(rawValue: "StartupWindowController")) as? StartupWindowController
		guard let wc = startupWindowController else { fatalError("failed to load startup window controller") }
		startupController = startupWindowController!.contentViewController as? StartupController
		assert(startupController != nil)
		wc.window?.makeKeyAndOrderFront(self)
		assert(wc.window!.isVisible)
		assert(wc.contentViewController?.view.window == wc.window)
		
		//move to the next stage
		advanceStartupStage()
	}
	
	//advances to the next startup stage
	fileprivate func advanceStartupStage() {
		guard let setupWC = startupWindowController else { fatalError("advanceStartupStage() called without a setup controller") }
		switch startupController!.stage {
		case .initial:
			startupController!.stage = .localLogin
			startLoginProcess()
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
		startupWindowController?.window?.orderOut(nil)
		let alert = NSAlert()
		alert.messageText = "Error starting application"
		alert .informativeText = error.nestedDescription ?? error.localizedDescription
		alert.addButton(withTitle: "Quit")
		alert.runModal()
		NSApp.terminate(self)
	}
	
	/// attempt login on host. advances to next startup stage if successful. Handles error by fatal error (if local), or re-prompting for login info if remote
	private func performLogin(host: ServerHost, password: String) {
		let loginFactory = LoginFactory()
		loginFactory.login(to: host, as: host.user, password: password).observe(on: UIScheduler()).startWithResult { result in
			guard let conInfo = result.value else {
				var message = result.error?.nestedError?.localizedDescription ?? result.error?.localizedDescription
				let nestederror = result.error!.nestedError as? NetworkingError
				if nestederror != nil,
					case let NetworkingError.invalidHttpStatusCode(rsp) = nestederror!,
					rsp.statusCode == 401
				{
					message = "invalid userid or password"
				}
				self.promptToLogin(previousErrorMessage: message ?? "unknown error")
				return
			}
			UserDefaults.standard[.currentCloudHost] = host
			// only close login window if it was created/shown
			if let loginWindowController = self.loginWindowController {
				self.startupWindowController!.window!.endSheet(loginWindowController.window!)
				self.loginController = nil
				self.loginWindowController = nil
			}
			self.connectionManager.currentConnection = conInfo
			do {
				try Keychain().setString(host.keychainKey, value: password)
			} catch {
				Log.error("error saving password to keychain: \(error)", .app)
			}
			self.advanceStartupStage()
		}
	}
	
	/// display UI for login info
	private func promptToLogin(previousErrorMessage: String? = nil) {
		if nil == loginWindowController {
			loginWindowController = mainStoryboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier(rawValue: "LoginWindowController")) as? NSWindowController
			loginController = loginWindowController?.contentViewController as? LoginViewController
		}
		guard let loginWindowController = loginWindowController , let loginController = loginController else { fatalError("failed to load login window") }
		loginController.initialHost = UserDefaults.standard[.currentCloudHost]
		loginController.statusMessage = previousErrorMessage ?? ""
		loginController.completionHandler = { host in
			guard let host = host else {
				self.startupWindowController!.window!.endSheet(loginWindowController.window!)
				NSApp.terminate(nil)
				return
			}
			self.performLogin(host: host, password: loginController.enteredPassword)
		}
		startupWindowController!.window!.beginSheet(loginWindowController.window!) { _ in }
	}
	
	/// if dockerEnabled, starts local login. If remote and there is a password in the keychain, attempts to login. Otherise, prompts for login info.
	private func startLoginProcess() {
		let keychain = Keychain()
		if let host = UserDefaults.standard[.currentCloudHost], host.user.count > 0 {
			if let password = keychain.getString(host.keychainKey) {
				performLogin(host: host, password: password)
				return
			}
		}
		promptToLogin()
	}
	
	private func showOnboarding() {
		if nil == onboardingController {
			// swiftlint:disable:next force_cast
			onboardingController = (mainStoryboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier(rawValue: "OnboardingWindowController")) as! OnboardingWindowController)
			onboardingController?.viewController.conInfo = connectionManager.currentConnection
			onboardingController?.viewController.actionHandler = { message in
				switch message {
				case .add:
					self.newWorkspace(nil)
				case .open(let wspace):
					self.openLocalSession(for: wspace.identifier)
				case .remove(let wspace):
					let client = Rc2RestClient(self.connectionManager.currentConnection!)
					client.remove(workspace: wspace).observe(on: UIScheduler()).startWithResult { result in
						if let err = result.error {
							self.appStatus?.presentError(err, session: nil)
							return
						}
						Log.info("workspace \(wspace.wspaceId) removed")
					}
				}
			}
		}
		onboardingController!.window?.makeKeyAndOrderFront(self)
	}
	
	private func restoreSessions() {
		guard sessionsBeingRestored.count > 0 else { advanceStartupStage(); return }
		for ident in self.sessionsBeingRestored.keys {
			openLocalSession(for: ident)
		}
		//TODO: use startupController for progress, perform async
	}
}
