//
//  EventTypes.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Freddy

public protocol EventData {
	init(json: JSON) throws
	var id: String { get }
	var time: Date { get }
	var attributes: [String: String]? { get }
}

public enum EventType {
	case container(ContainerEvent)
	case image(ImageEvent)
	case plugin(JSON)
	case volume(VolumeEvent)
	case network(NetworkEvent)
	case daemon(JSON)
	
	static func parse(json: JSON) throws -> EventType? {
		switch try json.getString(at: "Type") {
		case "container":
			return .container(try ContainerEvent(json: json))
		case "image":
			return .image(try ImageEvent(json: json))
		case "volume":
			return .volume(try VolumeEvent(json: json))
		case "network":
			return .network(try NetworkEvent(json: json))
		case "plugin":
			return .plugin(json)
		case "daemon":
			return .daemon(json)
		default:
			return nil
		}
	}
}

public struct ContainerEvent: EventData, CustomStringConvertible {
	public enum Action: String {
		case attach
		case commit
		case copy
		case create
		case destroy
		case detach
		case die
		case exec_create
		case exec_detach
		case exec_start
		case export
		case health_status
		case kill
		case oom
		case pause
		case rename
		case resize
		case restart
		case start
		case stop
		case top
		case unpause
		case update
	}

	public let id: String
	public let action: Action
	public let time: Date
	public let attributes: [String: String]?
	
	public init(json: JSON) throws {
		try id = json.getString(at: "id")
		try time = Date(timeIntervalSince1970: json.getDouble(at: "time"))
		attributes = try json.decodedDictionary(at: "Actor", "Attributes", alongPath: .missingKeyBecomesNil)
		guard let decodedAction = Action(rawValue: try  json.getString(at: "Action")) else {
			throw DockerError.unsupportedEvent
		}
		action = decodedAction
	}
	
	public var description: String {
		return "container event: \(action), name: \(attributes?["name"] ?? "n/a") time:\(time)"
	}
}

public struct ImageEvent: EventData, CustomStringConvertible {
	public enum Action: String {
		case delete
		case importEvt //import is a swift keyword
		case load
		case pull
		case push
		case save
		case tag
		case untag
	}
	
	public let id: String
	public let action: Action
	public let time: Date
	public let attributes: [String: String]?

	public init(json: JSON) throws {
		try id = json.getString(at: "id")
		try time = Date(timeIntervalSince1970: json.getDouble(at: "time"))
		attributes = try json.decodedDictionary(at: "Actor", "Attributes", alongPath: .missingKeyBecomesNil)
		guard let decodedAction = Action(rawValue: try  json.getString(at: "Action")) else {
			throw DockerError.unsupportedEvent
		}
		action = decodedAction
	}

	public var description: String {
		return "Image event: \(action), id: \(id), time:\(time)"
	}
}

public struct NetworkEvent: EventData, CustomStringConvertible {
	public enum Action: String {
		case create
		case connect
		case disconnect
		case destroy
	}
	
	public let id: String
	public let name: String
	public let action: Action
	public let time: Date
	public let attributes: [String: String]?

	public init(json: JSON) throws {
		try id = json.getString(at: "id")
		try time = Date(timeIntervalSince1970: json.getDouble(at: "time"))
		try name = json.getString(at: "Actor", "Attributes", "name")
		attributes = try json.decodedDictionary(at: "Actor", "Attributes", alongPath: .missingKeyBecomesNil)
		guard let decodedAction = Action(rawValue: try  json.getString(at: "Action")) else {
			throw DockerError.unsupportedEvent
		}
		action = decodedAction
	}

	public var description: String {
		return "Network event: \(action), network: \(name), time:\(time)"
	}
}

public struct VolumeEvent: EventData, CustomStringConvertible {
	public enum Action: String {
		case create, mount, unmount, destroy
	}
	public let action: Action
	public let container: String
	public let volumeId: String
	public let driver: String?
	public let id: String
	public let time: Date
	public let attributes: [String: String]?

	public init(json: JSON) throws {
		try id = json.getString(at: "id")
		try volumeId = json.getString(at: "Action", "ID")
		try time = Date(timeIntervalSince1970: json.getDouble(at: "time"))
		container = try json.getString(at: "Actor", "ID")
		driver = try? json.getString(at: "Actor", "driver")
		attributes = try json.decodedDictionary(at: "Actor", "Attributes", alongPath: .missingKeyBecomesNil)
		guard let decodedAction = Action(rawValue: try  json.getString(at: "Action")) else {
			throw DockerError.unsupportedEvent
		}
		action = decodedAction
	}
	
	public var description: String {
		return "Volume event: \(action), volume: \(volumeId), time:\(time)"
	}
}
