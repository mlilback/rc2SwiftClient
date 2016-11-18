//
//  AppStatus.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import ClientCore
import Networking
import ReactiveSwift

public class AppStatus: NSObject {
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
		super.init()
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
			self._currentProgress?.rc2_addCompletionHandler() {
				self.updateStatus(nil)
			}
		}
		NotificationCenter.default.postNotificationNameOnMainThread(Notifications.AppStatusChanged, object: self)
	}
	
	open func presentError(_ error: NSError, session: AnyObject?) {
		fatalError("subclasses must override prsentError()")
	}
	
	open func presentAlert(_ session:AnyObject?, message:String, details:String, buttons:[String], defaultButtonIndex:Int, isCritical:Bool, handler:((Int) -> Void)?)
	{
		fatalError("subclasses must override prsentAlert()")
	}
	
}

//Session class is a pass through variable, this protocol needs to know nothing about it
@objc protocol OAppStatus: class {
	///The NSProgress that is blocking the app. The AppStatus will observe the progress and when it is complete, set the current status to nil. Posts AppStatusChangedNotification when changed
	var currentProgress: Progress? { get set }
	///presents an error via NSAlert/UIAlert
	func presentError(_ error: NSError, session: AnyObject?)
	///presents a NSAlert/UIAlert with an optional callback. The handler is expect to set the currentProgress to nil if error finished an operation
	//swiftlint:disable:next function_parameter_count
	func presentAlert(_ session: AnyObject?, message: String, details: String, buttons: [String], defaultButtonIndex: Int, isCritical: Bool, handler: ((Int) -> Void)?)
}

extension OAppStatus {
	///convience property
	var busy: Bool { return currentProgress != nil }

	///convience property for localized description of current progress
	var statusMessage: String? { return currentProgress?.localizedDescription }

	///prsents a NSAlert/UIAlert with an optional callback
	func presentAlert(_ session: AnyObject, message: String, details: String, handler: ((Int) -> Void)? = nil)
	{
		presentAlert(session, message:message, details:details, buttons:[], defaultButtonIndex:0, isCritical:false, handler:handler)
	}

	///prsents a NSAlert/UIAlert with an optional callback
	func presentAlert(_ session: AnyObject, message: String, details: String, buttons: [String], handler: ((Int) -> Void)? = nil)
	{
		presentAlert(session, message: message, details: details, buttons: buttons, defaultButtonIndex: 0, isCritical: false, handler: handler)
	}

	///prsents a NSAlert/UIAlert with an optional callback
	func presentAlert(_ session: AnyObject, message: String, details: String, buttons: [String], defaultButtonIndex: Int, handler: ((Int) -> Void)? = nil)
	{
		presentAlert(session, message: message, details: details, buttons: buttons, defaultButtonIndex: defaultButtonIndex, isCritical: false, handler: handler)
	}

}
