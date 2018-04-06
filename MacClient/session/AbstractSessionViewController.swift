//
//  AbstractSessionViewController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import Rc2Common
import Networking
import SwiftyUserDefaults

class AbstractSessionViewController: NSViewController {
	weak var sessionOptional: Session? { didSet { sessionChanged() } }
	///convience accessor so don't have to constantly unwrap optional
	var session: Session {
		assert(sessionOptional != nil, "session accessed when doesn't exist")
		return sessionOptional!
	}
	//injected on load
	weak var appStatus: MacAppStatus? { didSet {
		appStatusChanged()
	} }
	
	deinit {
		NotificationCenter.default.removeObserver(self)
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

func firstChildViewController<T>(_ rootController: NSViewController) -> T? {
	return firstRecursiveDescendent(rootController,
		children: { return $0.childViewControllers },
		filter: { return $0 is T }) as? T
}
