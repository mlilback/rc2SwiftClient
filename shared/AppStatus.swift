//
//  AppStatus.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

@objc protocol AppStatus {
	var currentProgress: NSProgress? { get }
	var busy: Bool { get }
	var statusMessage: NSString { get }
	func updateStatus(progress: NSProgress?)
}
