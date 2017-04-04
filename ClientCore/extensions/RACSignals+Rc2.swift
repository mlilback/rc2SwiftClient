//
//  RACSignals+Rc2.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import ReactiveSwift
import SwiftyUserDefaults

public extension DefaultsKeys {
	public static let reactiveLoggingEnabled = DefaultsKey<Bool>("ReactiveLogging")
}

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
	
	/// if UserDefault .reactiveLoggingEnabled is true, logs all events that the receiver sends.
	/// By default, it will print to the standard output.
	///
	/// - parameters:
	///   - identifier: a string to identify the SignalProducer firing events.
	///   - events: Types of events to log.
	///   - fileName: Name of the file containing the code which fired the
	///               event.
	///   - functionName: Function where event was fired.
	///   - lineNumber: Line number where event was fired.
	///
	/// - returns: Signal producer that, when started, logs the fired events.
	public func optionalLog(_ identifier: String = "", events: Set<LoggingEvent.SignalProducer>? = nil, fileName: String = #file, functionName: String = #function, lineNumber: Int = #line) -> SignalProducer<Value, Error>
	{
		guard UserDefaults.standard[.reactiveLoggingEnabled] else { return self }
		//if events not specified, limit which ones we watch
		var myEvents = Set<LoggingEvent.SignalProducer>([.started, .completed, .failed])
		if events != nil { myEvents = events! }
		//strip most of the filename 'cause it is too long
		var myFilename = fileName
		if let idx = fileName.range(of: "/", options: .backwards) {
			myFilename = fileName.substring(from: idx.lowerBound)
		}
		return logEvents(identifier: identifier, events: myEvents, fileName: myFilename, functionName: functionName, lineNumber: lineNumber)
	}
}
