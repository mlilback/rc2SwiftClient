//
//  KeyValueObserver.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//
// Based on https://gist.github.com/rectalogic/92541de247ba17050d9a

import Foundation

typealias KVObserver = (source: NSObject, keyPath: String, change: [NSObject : AnyObject]?) -> Void

class KVOContext {
	private let source: NSObject
	private let keyPath: String
	private let observer: KVObserver
	
	func asPointer() -> UnsafeMutablePointer<KVOContext> {
		return UnsafeMutablePointer<KVOContext>(Unmanaged<KVOContext>.passUnretained(self).toOpaque())
	}
	
	class func fromPointer(pointer: UnsafeMutablePointer<KVOContext>) -> KVOContext {
		return Unmanaged<KVOContext>.fromOpaque(COpaquePointer(pointer)).takeUnretainedValue()
	}
	
	init(source: NSObject, keyPath: String, observer: KVObserver) {
		self.source = source
		self.keyPath = keyPath
		self.observer = observer
	}
	
	func invokeCallback(change: [NSObject : AnyObject]?) {
		observer(source: source, keyPath: keyPath, change: change)
	}
	
	deinit {
		source.removeObserver(defaultKVODispatcher, forKeyPath: keyPath, context: self.asPointer())
	}
}

class KVODispatcher : NSObject {
	override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>) {
		KVOContext.fromPointer(UnsafeMutablePointer<KVOContext>(context)).invokeCallback(change)
	}
}

private let defaultKVODispatcher = KVODispatcher()

extension NSObject {
	///will call observerChange immediately with the current value
	func addKeyValueObserver(keyPath: String, options: NSKeyValueObservingOptions, observeChange: KVObserver) -> KVOContext? {
		let context = KVOContext(source: self, keyPath: keyPath, observer: observeChange)
		self.addObserver(defaultKVODispatcher, forKeyPath: keyPath, options: options, context: context.asPointer())
		//invoke closure with initial value
		let curVal = self.valueForKeyPath(keyPath)
		if curVal != nil {
			observeChange(source: self, keyPath:keyPath, change:[NSKeyValueChangeKindKey:keyPath, NSKeyValueChangeNewKey:curVal!])
		}
		return context
	}
}
