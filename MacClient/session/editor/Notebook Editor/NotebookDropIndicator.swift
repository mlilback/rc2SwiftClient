//
//  NotebookDropIndicator.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

// The highlighted line where the dropped item will go:
class NotebookDropIndicator: NSView, NSCollectionViewElement {
	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
	}
	
	required init?(coder decoder: NSCoder) {
		super.init(coder: decoder)
	}
	
	override var wantsDefaultClipping: Bool { return false }
	
	// Draws the line using quartz:
	override func draw(_ dirtyRect: NSRect) {
		// Note: dirtyRect is set by layoutAttributesForDropTarget
		NSGraphicsContext.saveGraphicsState()
		defer { NSGraphicsContext.restoreGraphicsState() }
		NSColor.green.setFill()
		var rect = dirtyRect
		rect.origin.x = 0
		rect.fill()
	}
}

