//
//  AbstractSessionViewController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import ClientCore

class AbstractSessionViewController: NSViewController {
	dynamic weak var sessionOptional: Session? { didSet { sessionChanged() } }
	///convience accessor so don't have to constantly unwrap optional
	var session: Session { get { return sessionOptional! } }
	//injected by Swinject
	dynamic weak var appStatus: AppStatus? { didSet {
		appStatusChanged()
	} }
	
	deinit {
		NSNotificationCenter.defaultCenter().removeObserver(self)
	}

	override func viewDidLoad() {
		super.viewDidLoad()
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
