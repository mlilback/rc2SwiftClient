//
//  LoginViewController.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

class LoginViewController: NSViewController {
	///specify keys that should trigger KVO notification for canConnect property
	class func keyPathsForValuesAffectingCanConnect() -> Set<String>
	{
		return Set(["isLocalConnection", "selectedHost", "loginName", "password"])
	}

	class func checkForDocker() -> Bool {
		do {
			if let versionStr = try ShellCommands.stdout(for: "/usr/local/bin/docker-compose", arguments:["-v"], pattern:"version (.*), build (.*)", matchNumber:1)
			{
				let version = (versionStr as NSString).doubleValue
				if version >= 1.8 && version < 2.0 { return true }
			}
		} catch let err {
			print("got error \(err)")
		}
		return false
	}

	private let keychain = Keychain()
	
	///is the connection to the local server
	dynamic var isLocalConnection: Bool = true {
		didSet { adjustWorkspacePopUp() }
	}
	///The user specified login name
	dynamic var loginName : String = "" { didSet { adjustWorkspacePopUp() } }
	///The user specified password
	dynamic var password : String = ""
	///Value is save/restored to NSUserDefaults
	dynamic var autoSignIn : Bool = false
	///When true, controls are disabled and spinning progress indicator is enabled
	dynamic var isBusy : Bool = false
	///computed property to know if enough information is available to make a connection
	dynamic var canConnect: Bool {
		get {
			if isLocalConnection { return true }
			return selectedHost?.characters.count > 0 && loginName.characters.count > 0 && password.characters.count > 0
		}
	}

	///Closure called when the user presses the login button
	var completionHandler : ((controller: LoginViewController, userCanceled:Bool) -> Void)?
	///An array of host names to display to the user
	var hosts : [String] = ["localhost"] {
		didSet { selectedHost = hosts.first; hostArrayController?.content = hosts }
	}
	var workspaces : [String] = ["Default"]
	
	///The user selected host. Defaults to first host in hosts array
	dynamic var selectedHost : String? { didSet { adjustWorkspacePopUp() } }
	dynamic var selectedWorkspace: String?
	
	var dockerIsInstalled:Bool = { LoginViewController.checkForDocker() }()
	
	@IBOutlet var hostArrayController: NSArrayController!
	@IBOutlet var workspaceArrayController: NSArrayController!
	@IBOutlet weak var progressIndicator: NSProgressIndicator!
	@IBOutlet weak var loginField: NSTextField!
	
	override func viewWillAppear() {
		super.viewWillAppear()
		let defaults = NSUserDefaults.standardUserDefaults()
		if dockerIsInstalled {
			isLocalConnection = defaults.boolForKey(PrefKeys.LastWasLocal)
		} else {
			isLocalConnection = false
		}
		if let lastHost = defaults.stringForKey(PrefKeys.LastHost) {
			if hosts.contains(lastHost) { selectedHost = lastHost }
		}
		if let lastLogin = defaults.stringForKey(PrefKeys.LastLogin) {
			loginName = lastLogin
			password = keychain.getString("\(loginName)@\(selectedHost!)") ?? ""
		}
	}
	
	func workspaceNamesForSelectedHost() -> [String] {
		let defaults = NSUserDefaults.standardUserDefaults()
		var key = PrefKeys.LocalServerWorkspaces
		if !isLocalConnection {
			key = "ws//\(selectedHost!)//\(loginName)"
		}
		if let names = defaults.objectForKey(key) as? [String] where names.count > 0 {
			return names
		}
		return ["Default"]
	}

	//adjusts the workspace popup based on selectedHost and login
	func adjustWorkspacePopUp() {
		workspaces = workspaceNamesForSelectedHost()
		workspaceArrayController.content = workspaces
		var lastWspaceKey = PrefKeys.LastWorkspace
		if !isLocalConnection {
			lastWspaceKey = "\(lastWspaceKey).\(selectedHost).\(loginName)"
		}
		if let lastWspace = NSUserDefaults.standardUserDefaults().objectForKey(lastWspaceKey) as? String where workspaces.contains(lastWspace) {
			selectedWorkspace = lastWspace
		} else {
			selectedWorkspace = workspaces.first
		}
	}
	
	/**
		Owner should call this when the completionHandler has finished the async login attempt.
		This will set isBusy to false and show any error message.
		
		- Parameter error: nil if successful, a message to display if failed
	*/
	func loginAttemptComplete(error: String? = nil) {
		progressIndicator.stopAnimation(self)
		if error == nil {
			isBusy = false
			self.view.window?.orderOut(self)
			let defaults = NSUserDefaults.standardUserDefaults()
			defaults.setBool(isLocalConnection, forKey: PrefKeys.LastWasLocal)
			if isLocalConnection {
				defaults.removeObjectForKey(PrefKeys.LastLogin)
				defaults.removeObjectForKey(PrefKeys.LastHost)
				defaults.setObject(selectedWorkspace, forKey: PrefKeys.LastWorkspace)
			} else {
				defaults.setObject(loginName, forKey: PrefKeys.LastLogin)
				defaults.setObject(selectedHost, forKey: PrefKeys.LastHost)
				defaults.setObject(selectedWorkspace, forKey: "\(PrefKeys.LastWorkspace).\(selectedHost).\(loginName)")
				do {
					try keychain.setString("\(loginName)@\(selectedHost!)", value: password)
				} catch let error {
					log.warning("got error saving to keychain: \(error)")
				}
			}
			password = ""
		} else {
			log.error(error)
			let alert = NSAlert()
			alert.messageText = NSLocalizedString("Login Error", comment: "")
			alert.informativeText = error!
			alert.beginSheetModalForWindow(self.view.window!, completionHandler: { (response) -> Void in
				self.isBusy = false
				self.view.window!.makeFirstResponder(self.loginField)
			})
		}
	}
	
	@IBAction func cancel(sender:AnyObject) {
		completionHandler?(controller:self, userCanceled:true)
	}
	
	/// action used by the login button
	@IBAction func attemptLogin(sender:AnyObject) {
		isBusy = true
		progressIndicator.startAnimation(self)
		completionHandler!(controller: self, userCanceled:false)
	}
}

