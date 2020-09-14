//
//  LoginViewController.swift
//
//  Copyright ©2018 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import Networking

class LoginViewController: NSViewController {
	@IBOutlet private weak var serverPopUp: NSPopUpButton!
	@IBOutlet private weak var userField: NSTextField!
	@IBOutlet private weak var passwordField: NSTextField!
	@IBOutlet private weak var loginButon: NSButton!
	@IBOutlet private weak var statusField: NSTextField!
	@IBOutlet private weak var progressSpinner: NSProgressIndicator!

	var initialHost: ServerHost?
	var enteredPassword: String { return passwordField.stringValue }
	var selectedHost: ServerHost?

	var statusMessage: String { get { return statusField.stringValue } set { statusField.stringValue = newValue } }
	var userLogin: String { get { return userField.stringValue } set { userField.stringValue = newValue } }

	var completionHandler: ((ServerHost?) -> Void)?

	override func viewWillAppear() {
		super.viewWillAppear()
		statusField.stringValue = ""
		userField.stringValue = initialHost?.user ?? ""
		passwordField.stringValue = ""
		serverPopUp.selectItem(at: initialHost?.name == ServerHost.betaHost.name ? 1 : 0)
		loginButon.isEnabled = false
	}

	func clearPassword() {
		passwordField.stringValue = ""
	}

	@IBAction func cancelLogin(_ sender: Any?) {
		completionHandler?(nil)
	}

	@IBAction func performLogin(_ sender: Any?) {
		// TODO: login button should be disabled until values are entered
		guard userField.stringValue.count > 0, passwordField.stringValue.count > 0 else {
			NSSound.beep()
			return
		}
		let baseHost: ServerHost = serverPopUp.indexOfSelectedItem == 0 ? .cloudHost : .betaHost
		selectedHost = ServerHost(name: baseHost.name, host: baseHost.host, port: baseHost.port, user: userField.stringValue, urlPrefix: baseHost.urlPrefix, secure: true)
		completionHandler?(selectedHost)
	}
}

extension LoginViewController: NSTextFieldDelegate {
	func controlTextDidChange(_ obj: Notification) {
		let userValid = userField.stringValue.count > 3
		let passValid = passwordField.stringValue.count > 4
		loginButon.isEnabled = userValid && passValid
	}

	func control(_ control: NSControl, isValidObject obj: Any?) -> Bool {
		guard obj != nil else { return false }
		let userValid = userField.stringValue.count > 3
		let passValid = passwordField.stringValue.count > 4
		loginButon.isEnabled = userValid && passValid
		if control == userField { return userValid }
		if control == passwordField { return passValid }
		return true
	}
}
