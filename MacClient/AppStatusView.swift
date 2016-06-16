//
//  AppStatusView.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

class AppStatusView: NSView {
	@IBOutlet var textField: NSTextField?
	@IBOutlet var progress: NSProgressIndicator?
	@IBOutlet var determinateProgress: NSProgressIndicator? {
		get { return self.realDetProgress }
		set { self.realDetProgress = newValue }
	}
	private var realDetProgress:NSProgressIndicator?

	@IBOutlet var cancelButton: NSButton?
	weak var appStatus: AppStatus? { didSet { self.statusChanged(nil) } }
	var progressContext: KVObserver?
	
	override var intrinsicContentSize:NSSize { return NSSize(width:220, height:22) }
	
	deinit {
		NSNotificationCenter.defaultCenter().removeObserver(self)
	}
	
	override func awakeFromNib() {
		super.awakeFromNib()
		dispatch_async(dispatch_get_main_queue()) {
			NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(AppStatusView.statusChanged(_:)), name: AppStatusChangedNotification, object: nil)
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
		if let txt = appStatus?.statusMessage {
			textField?.stringValue = txt
		}
		if let isBusy = appStatus?.busy where isBusy {
			if appStatus?.currentProgress?.indeterminate ?? true {
				progress?.startAnimation(self)
			} else {
				determinateProgress?.doubleValue = 0
				determinateProgress?.hidden = false
				progressContext = KVObserver(object: (appStatus?.currentProgress)!, keyPath: "fractionCompleted")
					{ prog, _, _ in
						self.determinateProgress?.doubleValue = prog.fractionCompleted
						self.textField?.stringValue = prog.localizedDescription
						if self.determinateProgress?.doubleValue >= 1.0 {
							dispatch_async(dispatch_get_main_queue()) {
								self.appStatus?.currentProgress = nil
							}
						}
					}
			}
			cancelButton?.hidden = appStatus?.currentProgress?.cancellable ?? false
		} else {
			progress?.stopAnimation(self)
			determinateProgress?.hidden = true
			cancelButton?.hidden = true
			progressContext?.cancel()
			progressContext = nil
		}
	}
	
	@IBAction func cancel(sender: AnyObject?) {
		if appStatus?.currentProgress?.cancellable ?? true {
			appStatus?.currentProgress?.cancel()
		}
	}
}
