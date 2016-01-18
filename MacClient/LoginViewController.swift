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
	
	private let keychain = Keychain()
	
	///The user specified login name
	dynamic var loginName : String?
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
		didSet { selectedHost = hosts.first; arrayController?.content = hosts }
	}
	///The user selected host. Defaults to first host in hosts array
	dynamic var selectedHost : String?
	
	@IBOutlet var arrayController: NSArrayController!
	@IBOutlet weak var progressIndicator: NSProgressIndicator!
	@IBOutlet weak var loginField: NSTextField!
	
	//TODO: autologin if have data from keychain
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

