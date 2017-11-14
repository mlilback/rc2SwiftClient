//
//  MacSplitter.swift
//  Rc2Client
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import ClientCore

@objc open class MacSplitter: NSView {
	override open func awakeFromNib() {
		super.awakeFromNib()
		wantsLayer = true
		let tarea = NSTrackingArea(rect: bounds, options: [.cursorUpdate, .inVisibleRect, .activeInKeyWindow], owner: self, userInfo: nil)
		addTrackingArea(tarea)
	}
	
	override open func draw(_ dirtyRect: NSRect) {
		var rect = bounds
		rect.size.width = 1
		rect.origin.x += 3
		let color = PlatformColor(hexString: "b3b3b3")!
		color.set()
		rect.fill()
	}
	
	override open func cursorUpdate(with event: NSEvent) {
		NSCursor.resizeLeftRight.set()
	}
}
