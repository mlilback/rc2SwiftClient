//
//  InputPrompter.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

typealias Validator = (String) -> Bool

class InputPrompter: NSObject {

	let promptString: String
	private(set) var stringValue: String = ""
	var minimumStringLength: Int = 1
	var validator: Validator?
	let requiredSuffix: String?
	
	fileprivate var parentWindow: NSWindow?
	@IBOutlet var window: NSWindow!
	@IBOutlet var textField: NSTextField!
	@IBOutlet var promptLabel: NSTextField!
	@IBOutlet var okButton: NSButton!
	fileprivate var validValue: Bool = false
	
	init(prompt: String, defaultValue: String, suffix: String? = nil) {
		self.promptString = prompt
		self.stringValue = defaultValue
		requiredSuffix = suffix
		super.init()
		guard let nib = NSNib(nibNamed: "InputPrompter", bundle: nil) else { fatalError() }
		nib.instantiate(withOwner: self, topLevelObjects: nil)
		assert(window != nil)
		assert(textField != nil)
		let formatter = PrompterFormatter()
		formatter.validator = {  self.validate(change: $0) }
		formatter.observer = observe
		formatter.requiredSuffix = requiredSuffix
		textField.formatter = formatter
	}
	
	func prompt(window parent: NSWindow, handler: @escaping (Bool, String?) -> Void) {
		parentWindow = parent
		textField?.stringValue = stringValue
		parent.beginSheet(window) { (response) in
			handler(response == NSModalResponseOK, self.stringValue)
		}
	}
	
	@IBAction func saveValue(_ sender: AnyObject) {
		stringValue = textField.stringValue
		print("saving \(stringValue)")
		parentWindow?.endSheet(window, returnCode: NSModalResponseOK)
	}
	
	@IBAction func cancel(_ sender: AnyObject) {
		parentWindow?.endSheet(window, returnCode: NSModalResponseCancel)
	}
	
	func observe(change: String) {
		let isValid = validate(change: change, ignoreSuffix: false)
		okButton.isEnabled = isValid
		textField.action = isValid ? #selector(InputPrompter.saveValue(_:)) : nil
	}

	func validate(change: String, ignoreSuffix: Bool = true) -> Bool {
		if requiredSuffix != nil {
			if !ignoreSuffix && !change.hasSuffix(requiredSuffix!) { return false }
			if let range = change.range(of: requiredSuffix!) {
				let woSuffix = change.substring(to: range.lowerBound)
				guard woSuffix.characters.count >= minimumStringLength else { return false }
			}
		}
		guard change.characters.count >= minimumStringLength else { return false }
		//if no validator, default to true
		guard validator?(change) ?? true else { return false }
		return true
	}
}

extension InputPrompter: NSTextFieldDelegate {
	func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool
	{
		if commandSelector == #selector(NSResponder.insertTab(_:)) {
			return true
		}
		return false
	}
}

class PrompterFormatter: Formatter {
	var validator: Validator?
	var observer: ((String) -> Void)?
	var requiredSuffix: String?
	
	override func string(for obj: Any?) -> String?
	{
		guard let strversion = obj as? String else { return nil }
		return strversion
	}
	
	override func getObjectValue(_ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?, for string: String, errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool
	{
		obj?.pointee = string as AnyObject?
		return true
	}
	
	override func isPartialStringValid(_ partialStringPtr: AutoreleasingUnsafeMutablePointer<NSString>, proposedSelectedRange proposedSelRangePtr: NSRangePointer?, originalString origString: String, originalSelectedRange origSelRange: NSRange, errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool
	{
		defer {
			observer?(partialStringPtr.pointee as String)
		}
		var proposedString = partialStringPtr.pointee
		if let desiredSuffix = requiredSuffix {
			// if the desiredSuffix is not at the end of the proposedString, append it
			let lastPeriod = proposedString.range(of: ".", options: .backwards)
			if lastPeriod.location == NSNotFound {
				proposedSelRangePtr?.pointee = NSRange(location: proposedString.length, length: 0)
				proposedString = proposedString.appending(desiredSuffix) as NSString
				partialStringPtr.pointee = proposedString
				return false
			}
		}
		guard validator?(proposedString as String) ?? true else { return true }
		return true
	}
}

