//
//  AppStatus.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

//Session class is a pass through variable, this protocol needs to know nothing about it
@objc protocol AppStatus: class {
	///The NSProgress that is blocking the app. The AppStatus will observe the progress and when it is complete, set the current status to nil. Posts AppStatusChangedNotification when changed
	var currentProgress: Progress? { get set }
	///presents an error via NSAlert/UIAlert
	func presentError(_ error: NSError, session: AnyObject?)
	///presents a NSAlert/UIAlert with an optional callback. The handler is expect to set the currentProgress to nil if error finished an operation
	//swiftlint:disable:next function_parameter_count
	func presentAlert(_ session: AnyObject?, message: String, details: String, buttons: [String], defaultButtonIndex: Int, isCritical: Bool, handler: ((Int) -> Void)?)
}

extension AppStatus {
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
