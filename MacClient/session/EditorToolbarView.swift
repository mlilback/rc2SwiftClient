//
//  EditorToolbarView.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

class EditorToolbarView: NSView {
	@IBOutlet var toolbarStackView: NSStackView!
	@IBOutlet var replaceStackView: NSStackView!
	@IBOutlet var replaceCheckbox: NSButton!
	@IBOutlet var viewStyleControl: NSSegmentedControl!
	@IBOutlet var searchField: NSSearchField!
	@IBOutlet var replaceField: NSTextField!
	@IBOutlet var matchNavButtons: NSSegmentedControl!
	@IBOutlet var doneButton: NSSegmentedControl!
	@IBOutlet var replaceActionButtons: NSSegmentedControl!

	var replacing: Bool {
		get { return replaceCheckbox.state == .on }
		set {
			replaceCheckbox.state = newValue ? .on : .off
			toggleReplaceView(nil)
		}
	}
		
	@IBAction func toggleReplaceView(_ sender: Any?) {
		replaceStackView.isHidden = replaceCheckbox.state == .off
	}

	@IBAction func changeSelectedMatchAction(_ sender: Any?) {
		
	}
	@IBAction func performReplaceAction(_ sender: Any?) {
		
	}
	
	override func draw(_ dirtyRect: NSRect) {
		super.draw(dirtyRect)
		NSColor(red: 0.965, green: 0.965, blue: 0.965, alpha: 1.0).setFill()
		bounds.fill()
	}
}
