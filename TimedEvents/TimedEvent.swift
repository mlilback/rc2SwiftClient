//
//  TimedEvent.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import MJLLogger

/// An immutable event to be handled at a scheduled time
public class TimedEvent {
	/// how often an event should be fired
	public enum Frequency {
		case oneTime
		case minutes(Int)
		case hours(Int)
		case days(Int)
		case weekly
		case monthly
		
		/// parses a dictionary created by serialize() into a Frequency
		static func deserialize(_ data: Dictionary<String, Any>) -> Frequency? {
			guard let name = data["case"] as? String else { return nil }
			switch name {
			case "oneTime":
				return .oneTime
			case "minutes":
				guard let mval = data["value"] as? Int else { return nil}
				return .minutes(mval)
			case "hours":
				guard let hval = data["value"] as? Int else { return nil}
				return .hours(hval)
			case "days":
				guard let dval = data["value"] as? Int else { return nil}
				return .days(dval)
			case "weekly":
				return .weekly
			case "monthly":
				return .monthly
			default:
				return nil
			}
		}
		
		// returns self as a dictionary that can be serialized as json/property list
		func serialize() -> Dictionary<String, Any> {
			if let associated = Mirror(reflecting: self).children.first {
				return ["case": associated.label!, "value": associated.value]
			}
			return ["case": String(describing: self)]
		}

		/// Calculates the next date according to this frequency
		///
		/// - Parameter from: the data to start from
		/// - Returns: the from date incremented by this frequency
		func scheduleNext(from: Date = Date()) -> Date {
			// not sure how date(byAdding:) can return nil since dates have to be a time since epoch, and you should be able to add any increment.
			switch self {
			case .oneTime:
				return from
			case .days(let numDays):
				return Calendar.current.date(byAdding: .day, value: numDays, to: from)!
			case .hours(let numHours):
				return Calendar.current.date(byAdding: .hour, value: numHours, to: from)!
			case .minutes(let mins):
				return Calendar.current.date(byAdding: .minute, value: mins, to: from)!
			case .monthly:
				return Calendar.current.date(byAdding: .month, value: 1, to: from)!
			case .weekly:
				return Calendar.current.date(byAdding: .weekOfYear, value: 1, to: from)!
			}
		}
	}
	
	struct EventError: Error {
		enum ErrorType {
			case serialization
		}
		let errorType: ErrorType
		let message: String
		
		init(_ type: ErrorType, _ message: String) {
			self.errorType = type
			self.message = message
		}
	}

	public let id: UUID
	public let domain: String
	public let type: String
	public let priority: DispatchQoS
	public fileprivate(set) var frequency: Frequency
	public fileprivate(set) var lastExecuted: Date?
	public fileprivate(set) var scheduledTime: Date?
	public fileprivate(set) var coalescedCount: Int
	
	public init(domain: String, type: String, priority: DispatchQoS = .default, frequency: Frequency = .oneTime, startingFrom: Date? = nil)
	{
		self.id = UUID()
		self.domain = domain
		self.type = type
		self.priority = priority
		self.frequency = frequency
		self.lastExecuted = nil
		self.scheduledTime = startingFrom
		self.coalescedCount = 0
	}

	fileprivate init(id: UUID = UUID(), domain: String, type: String, priority: DispatchQoS = .default, frequency: Frequency = .oneTime, lastExecuted: Date? = nil, scheduledTime: Date? = nil, coalescedCount: Int = 0)
	{
		self.id = id
		self.domain = domain
		self.type = type
		self.priority = priority
		self.frequency = frequency
		self.lastExecuted = lastExecuted
		self.scheduledTime = scheduledTime
		self.coalescedCount = coalescedCount
	}
	
	fileprivate init(_ dict: Dictionary<String, Any>) throws {
		guard let aStr = dict["id"] as? String, let anId = UUID(uuidString: aStr) else { throw EventError(.serialization, "id") }
		self.id = anId
		guard let aDomain = dict["domain"] as? String else { throw EventError(.serialization, "domain") }
		self.domain = aDomain
		guard let aType = dict["type"] as? String else { throw EventError(.serialization, "type") }
		self.type = aType
		guard let pdict = dict["priority"] as? Dictionary<String, Any>, let aQos = DispatchQoS(dictionary: pdict) else { throw EventError(.serialization, "priority") }
		self.priority = aQos
		guard let fdict = dict["frequency"] as? Dictionary<String, Any>, let aFreq = Frequency.deserialize(fdict) else { throw EventError(.serialization, "frequency") }
		self.frequency = aFreq
		if let lastExecTime = dict["lastExecuted"] as? TimeInterval {
			self.lastExecuted = Date(timeIntervalSinceReferenceDate: lastExecTime)
		}
		if let schedTime = dict["scheduledTime"] as? TimeInterval {
			self.scheduledTime = Date(timeIntervalSinceReferenceDate: schedTime)
		}
		self.coalescedCount = 0
	}
	
	private func serialize(date: Date?) -> TimeInterval {
		guard let date = date else { return 0 }
		return date.timeIntervalSinceReferenceDate
	}
	
	func serialize() -> Dictionary<String, Any> {
		return ["id": id.uuidString, "domain": domain, "type": type, "priority": priority.serialize(), "frequency": frequency.serialize(), "lastExecuted": serialize(date: lastExecuted), "scheduledTime": serialize(date: scheduledTime)]
	}
}

extension TimedEvent: Hashable {
	public func hash(into hasher: inout Hasher) {
		hasher.combine(ObjectIdentifier(self))
	}

	public static func == (lhs: TimedEvent, rhs: TimedEvent) -> Bool {
		return lhs.hashValue == rhs.hashValue
	}
}

public typealias TimedEventHandler = (TimedEvent) -> Void

/// Delegate that handles application-specific activites for the TimedEventManager
public protocol TimedEventDelegate {
	/// Retrieves the previously saved serialized event data
	///
	/// - Returns: the serialized event data
	func loadEventData() -> Data?
	
	/// Save the serialized event data to an appropriate storage mechanism
	///
	/// - Parameter data: the data to save
	/// - Throws: any error that occurs while saving. Throwing an error will possibly result in data loss.
	func save(eventData: Data) throws
}

public class TimedEventManager
{
	static public var shared: TimedEventManager {
		get { if _shared == nil { _shared = TimedEventManager() }; return _shared! }
		set { if _shared != nil { fatalError("shared instance already set") }; _shared = newValue }
	}
	static private var _shared: TimedEventManager?
	
	/// when set, any existing delegate's save(eventData:) method will be called, followed by the new delegate's loadEventData() method
	public var delegate: TimedEventDelegate? {
		willSet { if delegate != nil { saveEvents() } }
		didSet { if delegate != nil { loadEvents() } }
	}
	fileprivate var domainHandlers = [String: TimedEventHandler]()
	fileprivate let queue = DispatchQueue(label: "TimedEventManager")
	private var allEvents = Set<TimedEvent>()
	
	public init(delegate: TimedEventDelegate? = nil) {
		self.delegate = delegate
		DispatchQueue.main.async {
			self.loadEvents()
		}
	}
	
	public func register(domain: String, handler: TimedEventHandler?) {
		queue.sync {
			domainHandlers[domain] = handler
		}
	}
	
	public func deregisterAll() {
		queue.sync {
			domainHandlers.removeAll()
		}
	}
	
	public func domainsWithoutHandlers() -> [String] {
		return []
	}
	
	public func eraseEvents(domain: String) {
		
	}
	
	public func events(for domain: String, interval: DateInterval? = nil) -> [TimedEvent] {
		return []
	}
	
	public func cancel(event: TimedEvent) {
		
	}
	
	public func delay(event: TimedEvent, by interval: TimeInterval) -> TimedEvent {
		return event
	}
	
	private func loadEvents() {
		guard let data = delegate?.loadEventData() else {
			Log.error("failed to load data from delegate", .core)
			return
		}
		do {
			guard let eventData = try JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] else {
				Log.error("failed to load serialized data", .core)
				return
			}
			allEvents.removeAll()
			try eventData.forEach { allEvents.insert(try TimedEvent($0)) }
		} catch {
			Log.error("error loading events", .core)
		}
	}
	
	private func saveEvents() {
		let events = allEvents.map { $0.serialize() }
		do {
			let data = try JSONSerialization.data(withJSONObject: events, options: [])
			try delegate?.save(eventData: data)
		} catch {
			Log.error("error saving events", .core)
		}
	}
}

// extension to add serialization
fileprivate extension DispatchQoS {
	init?(dictionary: Dictionary<String, Any>) {
		guard let class_t = dictionary["class_t"] as? UInt32,
			let priority = dictionary["priority"] as? Int,
			let qos_class = DispatchQoS.QoSClass(rawValue: qos_class_t(class_t))
			else { return nil }
		self.init(qosClass: qos_class, relativePriority: priority)
	}
	
	func serialize() -> Dictionary<String, Any> {
		return ["class_t": qosClass.rawValue.rawValue, "priority": relativePriority]
	}
}

