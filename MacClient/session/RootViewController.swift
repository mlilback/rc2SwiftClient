//
//  RootViewController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

class RootViewController: AbstractSessionViewController {
	@IBOutlet var progressView: NSProgressIndicator?
	@IBOutlet var statusField: NSTextField?
	var statusTimer:NSTimer?
	dynamic var busy: Bool = false
	dynamic var statusMessage: String = ""
	
	func startTimer() {
		if statusTimer != nil && statusTimer!.valid { statusTimer?.invalidate() }
		statusTimer = NSTimer.scheduledTimerWithTimeInterval(3.0, target: self, selector: "clearStatus", userInfo: nil, repeats: false)
	}
	
	func clearStatus() {
		statusTimer?.invalidate()
		statusMessage = ""
	}
	
	//TODO: need to add overlay view that blocks all interaction while busy
	override func appStatusChanged() {
		NSNotificationCenter.defaultCenter().addObserverForName(AppStatusChangedNotification, object: nil, queue: nil) { (note) -> Void in
			guard self.appStatus != nil else {
				log.error("appStatus not set on RootViewController")
				return
			}
			self.busy = (self.appStatus?.busy)!
			self.statusMessage = (self.appStatus?.statusMessage)! as String
			if !self.busy { self.startTimer() }
		}
	}
}
