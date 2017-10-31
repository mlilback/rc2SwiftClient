//
//  EditableTableCellView.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

public class EditableTableCellView: NSTableCellView {
	/// a validation function called before editing is ended
	public var validator: ((String?) -> Bool)?
	fileprivate var currentCallback: ((String?) -> Void)?
	fileprivate var canceled: Bool = false
	
	public override var textField: NSTextField? { didSet { textField?.delegate = self } }
	
	/// Starts an edit on the textField, calling closure when finished
	///
	/// - Parameters:
	///   - select: should the value be selected. Defaults to true
	///   - completionHandler: a callback with the new value, or nil if the user canceled editing
	func editText(completionHandler: @escaping (String?) -> Void)
	{
		canceled = false
		currentCallback = completionHandler
	}
}

extension EditableTableCellView: NSTextFieldDelegate {
	public override func controlTextDidEndEditing(_ obj: Notification) {
		guard let text = textField?.stringValue, text.count > 0, !canceled else {
			currentCallback?(nil)
			return
		}
		currentCallback?(text)
		currentCallback = nil
	}
	
	public func control(_ control: NSControl, isValidObject obj: Any?) -> Bool {
		return validator?(obj as? String) ?? true
	}
	
	public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool
	{
		switch commandSelector {
			case #selector(NSResponder.cancelOperation(_:)):
				canceled = true
			case #selector(NSResponder.insertNewline(_:)):
				canceled = false
			default:
				return false
		}
		textView.window?.makeFirstResponder(nil)
		return true
	}
}
