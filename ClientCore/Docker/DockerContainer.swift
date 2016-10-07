//
//  DockerContainer.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import SwiftyJSON
import ReactiveSwift

public enum ContainerState: String {
	case notAvailable, created, restarting, running, paused, exited
}

//MARK: -
/// An enumeration of the container names used to provide services via Docker
public enum ContainerType: String {
	static let typeRegex: NSRegularExpression = try! NSRegularExpression(pattern: "rc2server/(appserver|dbserver|compute)", options: [])
	case dbserver, appserver, compute
	static let all:[ContainerType] = [.dbserver, .appserver, .compute]
	
	static func from(imageName:String) -> ContainerType? {
		guard let match = typeRegex.firstMatch(in: imageName, options: [], range: imageName.toNSRange) else {
			return nil
		}
		return ContainerType(rawValue: match.string(index: 1, forString: imageName) ?? "")
	}
}

/// Represents a container on the docker server
public final class DockerContainer: JSONSerializable {
	public let type: ContainerType
	public let name: String
	public private(set) var id: String
	public private(set) var imageName: String
	public let state: MutableProperty<ContainerState>
//	public private(set) var state: ContainerState
	var createInfo: JSON?
	
	/// - returns: true if we know the container exists on the server
	public var exists:Bool { return state.value != .notAvailable }
	
	/// create an empty container of the specified type
	/// - parameter type: the type of container to create
	public init(type:ContainerType) {
		self.type = type
		self.name = "rc2_\(type.rawValue)"
		self.id = ""
		self.imageName = "rc2server/\(type.rawValue)"
		self.state = MutableProperty(.notAvailable)
//		self.state = .notAvailable
	}

	/// creates a container from the json returned from the docker server. required as part of JSONSerializable
	public init?(json:JSON?) {
		guard let json = json else { return nil }
		//figure out the name and container type
		var inName:String?
		let names = json["Names"].arrayValue.map({ return $0.stringValue })
		if names.count > 0 {
			let nname = names.first!
			inName = nname.substring(from: nname.index(after: nname.startIndex)) //strip off the leading '/'
		}
		guard inName != nil else { return nil }
		guard let jtype = ContainerType.from(imageName:inName!) else { return nil }
		name = inName!
		type = jtype
		//these will be set by update
		imageName = ""
		id = ""
		state = MutableProperty(.notAvailable)
		do {
			try update(json:json)
		} catch {
			return nil
		}
	}

	/// updates the id, imageName, and state properties
	///
	/// - parameter json: the JSON to update from
	///
	/// - throws: an NSError with a Rc2ErrorCode
	func update(json:JSON) throws {
		guard let jid = json["Id"].string, let jiname = json["Image"].string,
			let jstateStr = json["State"].string,
			let jstate = ContainerState(rawValue:jstateStr) else
		{
			throw NSError.error(withCode: .invalidJson, description: "JSON missing required container property")
		}
		id = jid
		imageName = jiname
		state.value = jstate
	}
	
	public func serialize() throws -> JSON {
		return JSON(["Id": JSON(id), "Image": JSON(imageName), "Name": JSON([JSON(name)]), "State": JSON(state.value.rawValue)])
	}

	/// Updates the state of the container, useful for updating via a docker event
	///
	/// - parameter state: the new state of the container
	public func update(state:ContainerState) {
		self.state.value = state
		//don't use a state machine because we could become off from what docker says and need to correct"
	}
}

extension DockerContainer: Equatable {
	public static func == (lhs: DockerContainer, rhs: DockerContainer) -> Bool {
		return lhs.id == rhs.id && lhs.imageName == rhs.imageName && lhs.name == rhs.name && lhs.state.value == rhs.state.value
	}
}

extension Array where Element:DockerContainer {
	/// returns the first element of the specified container type
	///
	/// - parameter index: the type to find
	///
	/// - returns: the first container of specified type
	subscript(index: ContainerType) -> DockerContainer? {
		return self.filter({ $0.type == index }).first
	}
}
