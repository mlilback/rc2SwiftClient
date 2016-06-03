//
//  LoginViewController.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

class LoginViewController: NSViewController {
	///key for bool value in NSUserDefaults
	let AutoLoginPrefKey = "AutomaticallyLogin"
	let LastLoginNamePrefKey = "LastLoginName"
	let LastHostPrefKey = "LastHost"
	let LastWorkspacePrefKey = "LastWorkspace"
	
	private let keychain = Keychain()
	
	///The user specified login name
	dynamic var loginName : String? { didSet { adjustWorkspacePopUp() } }
	///The user specified password
	dynamic var password : String?
	///Value is save/restored to NSUserDefaults
	dynamic var autoSignIn : Bool = false
	///When true, controls are disabled and spinning progress indicator is enabled
	dynamic var isBusy : Bool = false
	///Closure called when the user presses the login button
	var completionHandler : ((controller: LoginViewController) -> Void)?
	///An array of host names to display to the user
	var hosts : [String] = ["localhost"] {
		didSet { selectedHost = hosts.first; hostArrayController?.content = hosts }
	}
	var workspaces : [String] = ["Default"]
	
	///The user selected host. Defaults to first host in hosts array
	dynamic var selectedHost : String? { didSet { adjustWorkspacePopUp() } }
	dynamic var selectedWorkspace: String?
	//used to lookup the values to show in the workspace popup
	var lookupWorkspaceArray: ((String, String) -> [String])?
	
	@IBOutlet var hostArrayController: NSArrayController!
	@IBOutlet var workspaceArrayController: NSArrayController!
	@IBOutlet weak var progressIndicator: NSProgressIndicator!
	@IBOutlet weak var loginField: NSTextField!
	
	override func viewWillAppear() {
		super.viewWillAppear()
		let defaults = NSUserDefaults.standardUserDefaults()
		if defaults.boolForKey(AutoLoginPrefKey) {
			autoSignIn = true
		}
		if let lastHost = defaults.stringForKey(LastHostPrefKey) {
			if hosts.contains(lastHost) { selectedHost = lastHost }
		}
		if let lastLogin = defaults.stringForKey(LastLoginNamePrefKey) {
			loginName = lastLogin
			password = keychain.getString("\(loginName!)@\(selectedHost!)")
		}
	}
	
	//adjusts the workspace popup based on selectedHost and login
	func adjustWorkspacePopUp() {
		workspaces = lookupWorkspaceArray?(selectedHost!, loginName ?? "") ?? ["Default"]
		workspaceArrayController.content = workspaces
		let lastWspace = "\(LastWorkspacePrefKey).\(selectedHost).\(loginName)"
		if let lastWspace = NSUserDefaults.standardUserDefaults().objectForKey(lastWspace) as? String where workspaces.contains(lastWspace) {
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
			defaults.setBool(autoSignIn, forKey: AutoLoginPrefKey)
			defaults.setObject(loginName, forKey: LastLoginNamePrefKey)
			defaults.setObject(selectedHost, forKey: LastHostPrefKey)
			defaults.setObject(selectedWorkspace, forKey: "\(LastWorkspacePrefKey).\(selectedHost).\(loginName)")
			do {
				try keychain.setString("\(loginName!)@\(selectedHost!)", value: password)
			} catch let error {
				log.warning("got error saving to keychain: \(error)")
			}
			password = nil
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
	
	/// action used by the login button
	@IBAction func attemptLogin(sender:AnyObject) {
		isBusy = true
		progressIndicator.startAnimation(self)
		completionHandler!(controller: self)
	}
}

