//
//  ConsoleTextField.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

class ConsoleTextField: NSTextField {
	//will be called when the contextual menu is about to be displayed so it can be adjusted/
	var adjustContextualMenu: ((fieldEditor:NSText, menu:NSMenu) -> NSMenu)?
	
	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
	}
	
	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}
	
	///For use in validateMenuItem to know if an item should be enabled
	func fieldOrEditorIsFirstResponder() -> Bool {
		return self.currentEditor() != nil
	}
	
	func updateContextMenu() {
		let editor = currentEditor() as NSText!
		if let handler = adjustContextualMenu, menu = editor.menu {
			editor.menu = handler(fieldEditor: editor, menu: menu)
		}
	}
	
	override func textDidBeginEditing(notification: NSNotification) {
		super.textDidBeginEditing(notification)
		updateContextMenu()
	}
	
	override func textDidEndEditing(notification: NSNotification) {
		super.textDidEndEditing(notification)
		currentEditor()?.menu = NSTextView.defaultMenu()
	}
	
	///This is a method of the NSTextViewDelegate protocol. When a TextField is being edited,
	/// the selection is maintained by the FieldEditor. The TextField is assigned as the
	/// FieldEditor's delegate. Implementing this method (NSTextField does not appear to implement it)
	/// is the only way to do anything when the text selection changes
	func textViewDidChangeSelection(note:NSNotification) {
		updateContextMenu()
	}
}

