//
//  DockerContainer.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Freddy
import ReactiveSwift

/// Possible states for a container
public enum ContainerState: String {
	case notAvailable, created, restarting, running, paused, exited

	/// convience array with all possible values
	static let all: [ContainerState] = [.notAvailable, .created, .restarting, .running, .paused, .exited]
	/// convience array with possible values for a container that actually exists
	static let valid: [ContainerState] = [.created, .restarting, .running, .paused, .exited]
}

public enum ContainerError: Error {
	case containsNoName
	case invalidContainerType
}

// MARK: -
/// An enumeration of the container names used to provide services via Docker
public enum ContainerType: String {
	case dbserver, appserver, compute

	// swiftlint:disable:next force_try
	static private let imageRegex: NSRegularExpression = try! NSRegularExpression(pattern: "rc2server/(appserver|dbserver|compute)", options: [])
	// swiftlint:disable:next force_try
	static private let containerRegex: NSRegularExpression = try! NSRegularExpression(pattern: "rc2_(appserver|dbserver|compute)", options: [])

	/// convience array with all possible values
	static let all: [ContainerType] = [.dbserver, .appserver, .compute]

	/// Convience initializer from an image name
	///
	/// - parameter imageName: image name in format "rc2server/<type>"
	///
	/// - returns: corresponding state or nil
	static func from(imageName: String) -> ContainerType? {
		guard let match = imageRegex.firstMatch(in: imageName, options: [], range: imageName.fullNSRange) else {
			return nil
		}
		return ContainerType(rawValue: match.string(index: 1, forString: imageName) ?? "")
	}

	/// Convience initializer from an image name
	///
	/// - parameter containerName: image name in format "rc2_<ype>"
	///
	/// - returns: corresponding state or nil
	static func from(containerName: String) -> ContainerType? {
		guard let match = containerRegex.firstMatch(in: containerName, options: [], range: containerName.fullNSRange) else {
			return nil
		}
		return ContainerType(rawValue: match.string(index: 1, forString: containerName) ?? "")
	}
}

/// Information about a container mount point
public struct DockerMount: JSONDecodable {
	public let name: String
	public let source: String
	public let destination: String
	public let readWrite: Bool

	public init(json: JSON) throws {
		name = try json.getString(at: "Name")
		source = try json.getString(at: "Source")
		destination = try json.getString(at: "Destination")
		readWrite = try json.getBool(at: "RW")
	}
}

/// Represents a container on the docker server
public final class DockerContainer: JSONDecodable {
	public let type: ContainerType
	public let name: String
	public private(set) var id: String
	public private(set) var imageId: String
	public private(set) var mountPoints: [DockerMount]
	public let state: MutableProperty<ContainerState>
	var createInfo: Data?

	/// - returns: true if we know the container exists on the server
	public var exists: Bool { return state.value != .notAvailable }

	/// Loads default containers from createInfo array under the key "containers"
	///
	/// - Parameter json: json with createInfo array at "containers"
	/// - Returns: array of containers
	public class func fromCreateInfoJson(json: JSON) -> [DockerContainer] {
		do {
			let cjson = try json.getArray(at: "containers")
			let containers = try cjson.map { createJson -> DockerContainer in
				guard let type = ContainerType.from(imageName: try createJson.getString(at: "Image")) else {
					fatalError("failed to find container type for \(createJson)")
				}
				return DockerContainer(type: type, createInfo: try createJson.serialize())
			}
			return containers
		} catch {
			fatalError("error parsing static json")
		}
	}

	/// create an empty container of the specified type
	/// - parameter type: the type of container to create
	public init(type: ContainerType, createInfo: Data) {
		self.type = type
		self.name = "rc2_\(type.rawValue)"
		self.id = ""
		self.imageId = ""
		self.state = MutableProperty(.notAvailable)
		self.mountPoints = []
		self.createInfo = createInfo
	}

	/// convenience initializer that return nil if an error was thrown by the JSON initializer
	convenience init?(from: JSON) {
		do {
			try self.init(json: from)
		} catch {
			return nil
		}
	}

	/// JSONDecodable support. not implemented in an extension because is not a convience initializer
	public init(json: JSON) throws {
		//figure out the name and container type
		var inName: String?
		let names = try json.decodedArray(at: "Names", type: String.self)
		if !names.isEmpty {
			let nname = names.first!
			inName = nname.substring(from: nname.index(after: nname.startIndex)) //strip off the leading '/'
		}
		guard inName != nil else { throw ContainerError.containsNoName }
		guard let jtype = ContainerType.from(containerName:inName!) else { throw ContainerError.invalidContainerType }
		name = inName!
		type = jtype
		//these will be set by update
		imageId = ""
		id = ""
		mountPoints = []
		state = MutableProperty(.notAvailable)
		try update(json:json)
	}

	/// updates the id, imageName, and state properties
	///
	/// - parameter json: the JSON to update from
	///
	func update(json: JSON) throws {
		let jid = try json.getString(at: "Id")
		let jimgId = try json.getString(at: "ImageID")
		let jstateStr = try json.getString(at: "State")
		guard let jstate = ContainerState(rawValue:jstateStr) else
		{
			throw DockerError.invalidJson
		}
		id = jid
		imageId = jimgId
		state.value = jstate
		mountPoints = try json.decodedArray(at: "Mounts", type: DockerMount.self)
	}

	/// Update this container to match another container
	///
	/// - parameter from: container to copy all non-constant values from
	func update(from: DockerContainer) {
		id = from.id
		imageId	= from.imageId
		state.value = from.state.value
		mountPoints = from.mountPoints
		createInfo = from.createInfo
	}

	/// Updates the state of the container, useful for updating via a docker event
	///
	/// - parameter state: the new state of the container
	public func update(state: ContainerState) {
		self.state.value = state
		//don't use a state machine because we could become off from what docker says and need to correct
	}
	
	/// injects the desired image tag/name (e.g. rc2server/dbserver:0.4.2)
	///
	/// - Parameter imageTag: the full docker image name, including version
	/// - Throws: errors from JSONSerialization calls
	func injectIntoCreate(imageTag: String) throws {
		assert(createInfo != nil)
		//have to do this via JSONSerialization as Freddy doesn't allow mutating parsed data
		// swiftlint:disable:next force_cast
		var info = try JSONSerialization.jsonObject(with: createInfo!, options: []) as! [String: Any]
		info["Image"] = imageTag
		createInfo = try JSONSerialization.data(withJSONObject: info, options: [])
	}
}

extension DockerContainer: JSONEncodable {
	public func toJSON() -> JSON {
		return .dictionary(["Id": .string(id), "ImageID": .string(imageId), "Name": [.string(name)], "State": .string(state.value.rawValue)])
	}
}

extension DockerContainer: Equatable {
	public static func == (lhs: DockerContainer, rhs: DockerContainer) -> Bool {
		return lhs.id == rhs.id && lhs.imageId == rhs.imageId && lhs.name == rhs.name && lhs.state.value == rhs.state.value
	}
}

extension Array where Element:DockerContainer {
	/// returns the first element of the specified container type
	///
	/// - parameter index: the type to find
	///
	/// - returns: the first container of specified type
	subscript(index: ContainerType) -> DockerContainer? {
		return self.first(where: { $0.type == index })
	}
}
