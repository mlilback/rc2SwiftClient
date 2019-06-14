//
//  AbstractSessionViewController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import Rc2Common
import Networking
import SwiftyUserDefaults

/// Base class for views that need access to the session
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
	
	/// allows subclasses to take action when the session has been set
	func sessionChanged() {
	}
	
	/// allows subclasses to take action when the MacAppStatus has been set
	func appStatusChanged() {
	}
	
}

func firstChildViewController<T>(_ rootController: NSViewController) -> T? {
	return firstRecursiveDescendent(rootController,
		children: { return $0.childViewControllers },
		filter: { return $0 is T }) as? T
}
