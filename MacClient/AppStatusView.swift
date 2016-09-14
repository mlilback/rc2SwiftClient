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
	fileprivate var realDetProgress:NSProgressIndicator?

	@IBOutlet var cancelButton: NSButton?
	weak var appStatus: AppStatus? { didSet { self.statusChanged(nil) } }
	var progressContext: KVObserver?
	
	override var intrinsicContentSize:NSSize { return NSSize(width:220, height:22) }
	
	deinit {
		NotificationCenter.default.removeObserver(self)
	}
	
	override func awakeFromNib() {
		super.awakeFromNib()
		DispatchQueue.main.async {
			NotificationCenter.default.addObserver(self, selector: #selector(AppStatusView.statusChanged(_:)), name: NSNotification.Name(rawValue: Notifications.AppStatusChanged), object: nil)
		}
	}
	
	override func draw(_ dirtyRect: NSRect) {
		NSGraphicsContext.current()?.saveGraphicsState()
		let path = NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4)
		path.addClip()
		NSColor.white.setFill()
		path.fill()
		NSColor.black.set()
		path.stroke()
		NSGraphicsContext.current()?.restoreGraphicsState()
		super.draw(dirtyRect)
	}

	func statusChanged(_ sender:AnyObject?) {
		textField?.stringValue = appStatus?.statusMessage ?? ""
		if let isBusy = appStatus?.busy , isBusy {
			if appStatus?.currentProgress?.isIndeterminate ?? true {
				progress?.startAnimation(self)
			} else {
				determinateProgress?.doubleValue = 0
				determinateProgress?.isHidden = false
				progressContext = KVObserver(object: (appStatus?.currentProgress)!, keyPath: "fractionCompleted")
					{ prog, _, _ in
						self.determinateProgress?.doubleValue = prog.fractionCompleted
						self.textField?.stringValue = prog.localizedDescription
						if self.determinateProgress?.doubleValue ?? 0 >= 1.0 {
							DispatchQueue.main.async() {
								self.appStatus?.currentProgress = nil
							}
						}
					}
			}
			cancelButton?.isHidden = appStatus?.currentProgress?.isCancellable ?? false
		} else {
			progress?.stopAnimation(self)
			determinateProgress?.isHidden = true
			cancelButton?.isHidden = true
			progressContext?.cancel()
			progressContext = nil
		}
	}
	
	@IBAction func cancel(_ sender: AnyObject?) {
		if appStatus?.currentProgress?.isCancellable ?? true {
			appStatus?.currentProgress?.cancel()
		}
	}
}
