//
//  SingleInputViewController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

/// InputPrompter won't work if a Formatter is needed on the text field. This version will work, but won't actually disable the save button since it is only called when focus is leaving the text field
class SingleInputViewController: NSViewController {
	@IBOutlet var textField: NSTextField?
	@IBOutlet var saveButton: NSButton?
	/// Closure called when the textField contents change to validate if save button should be enabled
	var enableSaveButton: ((Any) -> Bool)?
	/// Closure to execute when user selects save
	var saveAction: ((SingleInputViewController) -> Void)?
	
	@IBAction func save(_ sender: AnyObject?) {
		presentingViewController!.dismiss(self)
		saveAction?(self)
	}
	
	@IBAction func cancel(_ sender: AnyObject?) {
		presentingViewController!.dismiss(self)
	}
}

extension SingleInputViewController: NSTextFieldDelegate {
	func control(_ control: NSControl, isValidObject obj: Any?) -> Bool {
		guard obj != nil else { return false }
		saveButton!.isEnabled = enableSaveButton?(obj!) ?? true
		return saveButton!.isEnabled
	}
}
