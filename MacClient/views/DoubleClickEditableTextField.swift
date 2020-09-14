//
//  DoubleClickEditableTextField.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

class DoubleClickEditableTextField: NSTextField {
	override func viewDidMoveToWindow() {
		let ncenter = NotificationCenter.default
		if window == nil {
			ncenter.removeObserver(self, name: NSControl.textDidEndEditingNotification, object: self)
		} else {
			ncenter.addObserver(self, selector: #selector(stopEditing(_:)), name: NSControl.textDidEndEditingNotification, object: self)
		}
	}

	override func mouseDown(with event: NSEvent) {
		if event.clickCount == 2 && !self.isEditable {
			beginEditing()
		} else {
			super.mouseDown(with: event)
		}
	}

	func beginEditing() {
		isEditable = true
		backgroundColor = NSColor.white
		isSelectable = true
		selectText(self)
		needsDisplay = true
	}

	@objc func stopEditing(_ note: Notification) {
		isEditable = false
		backgroundColor = NSColor.clear
		isSelectable = false
		needsDisplay = true
	}
}
