//
//  MacSplitter.swift
//  Rc2Client
//
//  Created by Mark Lilback on 1/16/16.
//  Copyright © 2016 West Virginia University. All rights reserved.
//

import Cocoa

@objc public class MaacSplitter : NSView {
	override public func awakeFromNib() {
		wantsLayer = true
		let tarea = NSTrackingArea(rect: bounds, options: [.CursorUpdate, .InVisibleRect, .ActiveInKeyWindow], owner: self, userInfo: nil)
		addTrackingArea(tarea)
	}
	
	override public func drawRect(dirtyRect: NSRect) {
		var rect = bounds
		rect.size.width = 1
		rect.origin.x += 3
		let color = try! Color(hex: "b3b3b3")
		color.set()
		NSRectFill(rect)
	}
	
	override public func cursorUpdate(event: NSEvent) {
		NSCursor.resizeLeftRightCursor().set()
	}
}