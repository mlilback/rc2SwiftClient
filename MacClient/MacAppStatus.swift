//
//  MacAppStatus.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import Networking
import ReactiveSwift
import ClientCore
import os

class MacAppStatus {
	fileprivate dynamic var _currentProgress: Progress?
	fileprivate let _statusQueue = DispatchQueue(label: "io.rc2.statusQueue", qos: .userInitiated)
	public let getWindow: (Session?) -> NSWindow
	
	dynamic var currentProgress: Progress? {
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
	
	dynamic var statusMessage: String {
		get {
			var status = ""
			_statusQueue.sync { status = self._currentProgress?.localizedDescription ?? "" }
			return status
		}
	}
	
	init(windowAccessor:@escaping (Session?) -> NSWindow) {
		getWindow = windowAccessor
	}
	
	/// Used in a composed producer chain to update window progress indicator as operation is performed. will fatalError if busy
	///
	/// - Parameter producer: a SignalProducer that sends progress events from 0..1
	/// - Returns: a composed producer with an observer added
	func monitorProgress(producer: SignalProducer<Double, Rc2Error>) -> SignalProducer<Double, Rc2Error> {
		return producer.on(starting: {
		}, value: { (per) in
			print("update percent: \(per)")
		}, failed: { err in
		}, completed: {
			print("progress complete")
		}, interrupted: {
		})
	}
	
	func monitorProgress(signal: Signal<Double, Rc2Error>) {
		signal.observe { observer in
			
		}
	}
	
	@available(*, deprecated)
	func updateStatus(_ progress: Progress?) {
		assert(_currentProgress == nil || progress == nil, "can't set progress when there already is one")
		_statusQueue.sync {
			self._currentProgress = progress
			os_log("Progress no longer supported in AppStatus", log: .app, type: .error)
			//			self._currentProgress?.rc2_addCompletionHandler() {
			//				self.updateStatus(nil)
			//			}
		}
		NotificationCenter.default.postNotificationNameOnMainThread(Notifications.AppStatusChanged, object: self)
	}

	func presentError(_ error: Rc2Error, session: AnyObject?) {
		let alert = NSAlert()
		alert.messageText = error.localizedDescription
		alert.informativeText = error.nestedError?.localizedDescription ?? ""
		alert.addButton(withTitle: NSLocalizedString("Ok", comment: ""))
		alert.beginSheetModal(for: getWindow(session as? Session), completionHandler:nil)
	}
	
	func presentAlert(_ session:AnyObject?, message:String, details:String, buttons:[String], defaultButtonIndex:Int, isCritical:Bool, handler:((Int) -> Void)?)
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
		alert.beginSheetModal(for: getWindow((session as! Session)), completionHandler: { (rsp) in
			guard buttons.count > 1 else { return }
			DispatchQueue.main.async {
				//convert rsp to an index to buttons
				handler?(rsp - NSAlertFirstButtonReturn)
			}
		}) 
	}
}
