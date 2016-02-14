//
//  AppStatusView.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

class AppStatusView: NSView {
	var textField: NSTextField?
	var progress: NSProgressIndicator?
	var cancelButton: NSButton?
	var appStatus: AppStatus? { didSet { self.statusChanged(nil) } }
	
	override var intrinsicContentSize:NSSize { return NSSize(width:220, height:22) }
	
	override func awakeFromNib() {
		super.awakeFromNib()
		NSNotificationCenter.defaultCenter().addObserver(self, selector: "statusChanged:", name: AppStatusChangedNotification, object: nil)
	}
	
	func statusChanged(sender:AnyObject?) {
		if let txt = appStatus?.statusMessage as? String {
			textField?.stringValue = txt
		}
		if let isBusy = appStatus?.busy where isBusy {
			progress?.startAnimation(self)
			cancelButton?.hidden = appStatus?.cancelHandler == nil
		} else {
			progress?.stopAnimation(self)
			cancelButton?.hidden = true
		}
	}
	
	@IBAction func cancel(sender: AnyObject?) {
		if let handler = appStatus?.cancelHandler {
			handler(appStatus: appStatus!)
		}
	}
	
	override func drawRect(dirtyRect: NSRect) {
		NSGraphicsContext.currentContext()?.saveGraphicsState()
		let path = NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4)
		path.addClip()
		NSColor.whiteColor().setFill()
		path.fill()
		NSColor.blackColor().set()
		path.stroke()
		NSGraphicsContext.currentContext()?.restoreGraphicsState()
		super.drawRect(dirtyRect)
	}
}
