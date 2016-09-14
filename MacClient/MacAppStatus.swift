//
//  MacAppStatus.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

class MacAppStatus: NSObject, AppStatus {

	fileprivate dynamic var _currentProgress: Progress?
	fileprivate let _statusQueue = DispatchQueue(label: "io.rc2.statusQueue", qos: .userInitiated)
	fileprivate let getWindow: (Session?) -> NSWindow
	
	dynamic  var currentProgress: Progress? {
		get {
			var result: Progress? = nil
			_statusQueue.sync { result = self._currentProgress }
			return result
		}
		set { updateStatus(newValue) }
	}
	
	dynamic var busy: Bool {
		get {
			var result = false
			_statusQueue.sync { result = self._currentProgress != nil }
			return result
		}
	}
	
	dynamic var statusMessage: NSString {
		get {
			var status = ""
			_statusQueue.sync { status = self._currentProgress?.localizedDescription ?? "" }
			return status as NSString
		}
	}
	
	init(windowAccessor:@escaping (Session?) -> NSWindow) {
		getWindow = windowAccessor
		super.init()
	}
	
	func updateStatus(_ progress: Progress?) {
		assert(_currentProgress == nil || progress == nil, "can't set progress when there already is one")
		_statusQueue.sync {
			self._currentProgress = progress
			self._currentProgress?.rc2_addCompletionHandler() {
				self.updateStatus(nil)
			}
		}
		NotificationCenter.default.postNotificationNameOnMainThread(Notifications.AppStatusChanged, object: self)
	}
	
	func presentError(_ error: NSError, session:Session?) {
		let alert = NSAlert(error: error)
		alert.beginSheetModal(for: getWindow(session), completionHandler:nil)
	}
	
	func presentAlert(_ session:Session?, message:String, details:String, buttons:[String], defaultButtonIndex:Int, isCritical:Bool, handler:((Int) -> Void)?)
	{
		let alert = NSAlert()
		alert.messageText = message
		alert.informativeText = details
		if buttons.count == 0 {
			alert.addButton(withTitle: NSLocalizedString("Ok", comment: ""))
		} else {
			for aButton in buttons {
				alert.addButton(withTitle: aButton)
			}
		}
		alert.alertStyle = isCritical ? .critical : .warning
		alert.beginSheetModal(for: getWindow(session), completionHandler: { (rsp) in
			guard buttons.count > 1 else { return }
			DispatchQueue.main.async {
				//convert rsp to an index to buttons
				handler?(rsp - NSAlertFirstButtonReturn)
			}
		}) 
	}

}
