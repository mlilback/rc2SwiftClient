//
//  Atomic.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

///Uses a private DispatchQueue to provide atomic access to a value
public struct Atomic<T> {
	private var _value: T
	private let queue = DispatchQueue(label: "Atomic \(UUID().uuidString)")

	///atomic, thread-safe value property
	public var value: T {
		get { var val: T?; queue.sync { val = _value }; return val! }
		set { queue.sync { _value = newValue } }
	}

	///initialize with an initial variable
	public init(_ initialValue: T) {
		_value = initialValue
	}
}
