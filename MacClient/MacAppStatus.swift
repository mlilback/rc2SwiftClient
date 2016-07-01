//
//  MacAppStatus.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

class MacAppStatus: NSObject, AppStatus {

	private dynamic var _currentProgress: NSProgress?
	private let _statusQueue = dispatch_queue_create("io.rc2.statusQueue", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0))
	private let getWindow: (Session?) -> NSWindow
	
	dynamic  var currentProgress: NSProgress? {
		get {
			var result: NSProgress? = nil
			dispatch_sync(_statusQueue) { result = self._currentProgress }
			return result
		}
		set { updateStatus(newValue) }
	}
	
	dynamic var busy: Bool {
		get {
			var result = false
			dispatch_sync(_statusQueue) { result = self._currentProgress != nil }
			return result
		}
	}
	
	dynamic var statusMessage: NSString {
		get {
			var status = ""
			dispatch_sync(_statusQueue) { status = self._currentProgress?.localizedDescription ?? "" }
			return status
		}
	}
	
	init(windowAccessor:(Session?) -> NSWindow) {
		getWindow = windowAccessor
		super.init()
	}
	
	func updateStatus(progress: NSProgress?) {
		assert(_currentProgress == nil || progress == nil, "can't set progress when there already is one")
		dispatch_sync(_statusQueue) {
			self._currentProgress = progress
			self._currentProgress?.rc2_addCompletionHandler() {
				self.updateStatus(nil)
			}
		}
		NSNotificationCenter.defaultCenter().postNotificationNameOnMainThread(Notifications.AppStatusChanged, object: self)
	}
	
	func presentError(error: NSError, session:Session?) {
		let alert = NSAlert(error: error)
		alert.beginSheetModalForWindow(getWindow(session), completionHandler:nil)
	}
	
	func presentAlert(session:Session?, message:String, details:String, buttons:[String], defaultButtonIndex:Int, isCritical:Bool, handler:((Int) -> Void)?)
	{
		let alert = NSAlert()
		alert.messageText = message
		alert.informativeText = details
		if buttons.count == 0 {
			alert.addButtonWithTitle(NSLocalizedString("Ok", comment: ""))
		} else {
			for aButton in buttons {
				alert.addButtonWithTitle(aButton)
			}
		}
		alert.alertStyle = isCritical ? .CriticalAlertStyle : .WarningAlertStyle
		alert.beginSheetModalForWindow(getWindow(session)) { (rsp) in
			guard buttons.count > 1 else { return }
			dispatch_async(dispatch_get_main_queue()) {
				//convert rsp to an index to buttons
				handler?(rsp - NSAlertFirstButtonReturn)
			}
		}
	}

}