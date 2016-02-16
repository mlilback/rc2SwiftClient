//
//  AppStatusView.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

class AppStatusView: NSView {
	@IBOutlet var textField: NSTextField?
	@IBOutlet var progress: NSProgressIndicator?
	@IBOutlet var determinateProgress: NSProgressIndicator?
	@IBOutlet var cancelButton: NSButton?
	var appStatus: AppStatus? { didSet { self.statusChanged(nil) } }
	private var progressContext:KVOContext?
	
	override var intrinsicContentSize:NSSize { return NSSize(width:220, height:22) }
	
	override func awakeFromNib() {
		super.awakeFromNib()
		dispatch_async(dispatch_get_main_queue()) {
			NSNotificationCenter.defaultCenter().addObserver(self, selector: "statusChanged:", name: AppStatusChangedNotification, object: nil)
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

	func statusChanged(sender:AnyObject?) {
		if let txt = appStatus?.statusMessage as? String {
			textField?.stringValue = txt
		}
		if let isBusy = appStatus?.busy where isBusy {
			if appStatus?.currentProgress?.indeterminate ?? true {
				progress?.startAnimation(self)
			} else {
				determinateProgress?.doubleValue = 0
				determinateProgress?.hidden = false
				progressContext = appStatus?.currentProgress?.addKeyValueObserver("fractionCompleted", options: [])
				{ [weak self] (source, keypath, change) in
					let prog = source as! NSProgress
					self?.determinateProgress?.doubleValue = Double(prog.completedUnitCount) / Double(prog.totalUnitCount)
					if self?.determinateProgress?.doubleValue >= 1.0 {
						self?.appStatus?.updateStatus(nil)
					}
				}
			}
			cancelButton?.hidden = appStatus?.currentProgress?.cancellable ?? false
		} else {
			progress?.stopAnimation(self)
			determinateProgress?.hidden = true
			cancelButton?.hidden = true
			progressContext = nil
		}
	}
	
	@IBAction func cancel(sender: AnyObject?) {
		if appStatus?.currentProgress?.cancellable ?? true {
			appStatus?.currentProgress?.cancel()
		}
	}
}
