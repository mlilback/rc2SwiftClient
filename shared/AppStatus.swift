//
//  AppStatus.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

@objc protocol AppStatus {
	var busy: Bool { get }
	var statusMessage: NSString { get }
	var cancelHandler:((appStatus:AppStatus) -> Bool)? { get }
	func updateStatus(busy:Bool, message:String, cancelHandler:((appStatus:AppStatus) -> Bool)?)
}

extension AppStatus {
	func updateStatus(busy:Bool, message:String) {
		return updateStatus(busy, message:message, cancelHandler: nil)
	}
}
