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

public extension SignalProducer {
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
