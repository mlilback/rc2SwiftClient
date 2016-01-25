//
//  SpinLock.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

class Spinlock {
	private var _lock : OSSpinLock = OS_SPINLOCK_INIT
	
	func around(code: Void -> Void) {
		OSSpinLockLock(&self._lock)
		code()
		OSSpinLockUnlock(&self._lock)
	}
	
	func around<T>(code: Void -> T) -> T {
		OSSpinLockLock(&self._lock)
		let result = code()
		OSSpinLockUnlock(&self._lock)
		
		return result
	}
}
