//
//  AbstractSessionViewController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

class AbstractSessionViewController: NSViewController {
	dynamic var sessionOptional: Session?
	///convience accessor so don't have to constantly unwrap optional
	var session: Session { get { return sessionOptional! } }
	
	override func viewDidLoad() {
		super.viewDidLoad()
		NSNotificationCenter.defaultCenter().addObserverForName(CurrentSessionChangedNotification, object: nil, queue: nil) {
			self.sessionOptional = $0.object as! Session?
			self.sessionChanged()
		}
	}
	
	///for subclasses
	func sessionChanged() {
	}
}
