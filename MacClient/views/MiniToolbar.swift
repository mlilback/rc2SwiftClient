//
//  MiniToolbar.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

class MiniToolbar: NSView {
	override func draw(_ dirtyRect: NSRect) {
		super.draw(dirtyRect)
		NSColor(red: 0.965, green: 0.965, blue: 0.965, alpha: 1.0).setFill()
		bounds.fill()
	}
}
