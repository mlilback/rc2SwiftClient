//
//  MacSplitter.swift
//  SwiftClient
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import ClientCore

@objc public class MacSplitter : NSView {
	override public func awakeFromNib() {
		wantsLayer = true
		let tarea = NSTrackingArea(rect: bounds, options: [.CursorUpdate, .InVisibleRect, .ActiveInKeyWindow], owner: self, userInfo: nil)
		addTrackingArea(tarea)
	}
	
	override public func drawRect(dirtyRect: NSRect) {
		var rect = bounds
		rect.size.width = 1
		rect.origin.x += 3
		let color = try! PlatformColor(hex: "b3b3b3")
		color.set()
		NSRectFill(rect)
	}
	
	override public func cursorUpdate(event: NSEvent) {
		NSCursor.resizeLeftRightCursor().set()
	}
}
