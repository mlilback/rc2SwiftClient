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
	//injected by Swinject
	dynamic var appStatus: AppStatus? { didSet {
		appStatusChanged()
	} }
	
	override func viewDidLoad() {
		super.viewDidLoad()
		NSNotificationCenter.defaultCenter().addObserverForName(CurrentSessionChangedNotification, object: nil, queue: nil) {
			[unowned self] in 
			self.sessionOptional = $0.object as! Session?
			self.sessionChanged()
		}
	}
	
	///for subclasses
	func sessionChanged() {
	}
	
	func appStatusChanged() {
	}
}

func firstChildViewController<T>(rootController:NSViewController) -> T? {
	return firstRecursiveDescendent(rootController,
		children: { return $0.childViewControllers },
		filter: { return $0 is T }) as? T
}
