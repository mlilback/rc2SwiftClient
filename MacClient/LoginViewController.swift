//
//  LoginViewController.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

class LoginViewController: NSViewController {
	///key for bool value in NSUserDefaults
	let AutoLoginPrefKey = "AutomaticallyLogin"
	
	///The user specified login name
	var loginName : String?
	///The user specified password
	var password : String?
	///Value is save/restored to NSUserDefaults
	var autoSignIn : Bool = false
	///When true, controls are disabled and spinning progress indicator is enabled
	var isBusy : Bool = false
	///Closure called when the user presses the login button
	var completionHandler : ((controller: LoginViewController) -> Void)?
	///An array of host names to display to the user
	var hosts : [String] = ["localhost"] {
		didSet { selectedHost = hosts.first; arrayController?.content = hosts }
	}
	///The user selected host. Defaults to first host in hosts array
	var selectedHost : String?
	
	@IBOutlet var arrayController: NSArrayController!
	
	//TODO: load login/password from keychain
	//TODO: autologin if have data from keychain
	override func viewDidLoad() {
		super.viewDidLoad()
		if NSUserDefaults.standardUserDefaults().boolForKey(AutoLoginPrefKey) {
			autoSignIn = true
		}
	}

	override func viewWillDisappear() {
		super.viewWillDisappear()
		NSUserDefaults.standardUserDefaults().setBool(autoSignIn, forKey: AutoLoginPrefKey)
	}
	
	/** 
		Owner should call this when the completionHandler has finished the async login attempt.
		This will set isBusy to false and show any error message.
		
		- Parameter error: nil if successful, a message to display if failed
	*/
	func loginAttemptComplete(error: String? = nil) {
		isBusy = false
		if error != nil {
			//TODO: show error message
			log.error(error)
		} else {
			self.view.window?.orderOut(self)
			password = nil
		}
	}
	
	/// action used by the login button
	@IBAction func attemptLogin(sender:AnyObject) {
		completionHandler!(controller: self)
	}
}

