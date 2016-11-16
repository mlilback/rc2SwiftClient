//
//  RACSignals+Rc2.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import ReactiveSwift

public extension Signal {
	/// Ignores `value` events for the given interval. Forwards other events as they happen
	/// very useful for ignoring progress events until x seconds have passed
	///
	/// - parameters:
	///   - for: Interval to ignore `value` events.
	///
	/// - returns: A signal that will ignore `value` events for a time
	public func ignoreValues(for delay: TimeInterval) -> Signal<Value, Error> {
		precondition(delay >= 0)
		let startTime = Date.timeIntervalSinceReferenceDate
		return Signal { observer in
			return self.observe { event in
				switch event {
				case .failed, .interrupted, .completed:
					observer.action(event)

				case .value:
					if Date.timeIntervalSinceReferenceDate - startTime >= delay {
						observer.action(event)
					}
				}
			}
		}
	}
}

public extension SignalProducer {
	/// Ignores `value` events for the given interval. Forwards other events as they happen
	/// very useful for ignoring progress events until x seconds have passed
	///
	/// - parameters:
	///   - for: Interval to ignore `value` events.
	///
	/// - returns: A signal producer that will ignore `value` events for a time
	public func ignoreValues(for delay: TimeInterval) -> SignalProducer<Value, Error> {
		return lift { $0.ignoreValues(for: delay) }
	}
}
