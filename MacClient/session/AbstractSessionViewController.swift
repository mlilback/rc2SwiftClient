//
//  AbstractSessionViewController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

public class AbstractSessionViewController : NSViewController {
	dynamic var sessionOptional: Session?
	///convience accessor so don't have to constantly unwrap optional
	var session: Session { get { return sessionOptional! } }
	private var sessionContext: KVOContext?
	
	override public func viewDidLoad() {
		super.viewDidLoad()
		sessionContext = Session.manager.addKeyValueObserver("currentSession", options: [.New]) { (source, keyPath, change) -> Void in
			self.sessionOptional = Session.manager.currentSession
			self.sessionChanged()
		}
	}
	
	deinit {
		sessionContext = nil //unregisters kvo observer
	}
	
	///for subclasses
	func sessionChanged() {
	}
}
