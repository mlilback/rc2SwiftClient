//
//  DockerContainer.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import SwiftyJSON

public enum ContainerState: String {
	case created, restarting, running, paused, exited
}


public struct DockerContainer: JSONSerializable, Named {
	public let id:String
	public let imageName:String
	public let name:String
	public let state:ContainerState
	
	public init?(json:JSON?) {
		guard let json = json else { return nil }
		id = json["Id"].stringValue
		var inName = ""
		let names = json["Names"].arrayValue.map({ return $0.stringValue })
		if names.count > 0 {
			let nname = names.first!
			inName = nname.substring(from: nname.index(after: nname.startIndex)) //strip off the leading '/'
		}
		name = inName
		imageName = json["Image"].stringValue
		guard let parsedState = ContainerState(rawValue: json["State"].stringValue) else { return nil }
		state = parsedState
	}

	public func serialize() throws -> JSON {
		return JSON(["Id": JSON(id), "Image": JSON(imageName), "Name": JSON([JSON(name)]), "State": JSON(state.rawValue)])
	}
	
	public func isNamed(_ str: String) -> Bool {
		return name == str || name == "/\(str)"
	}
}

extension DockerContainer: Equatable {
	public static func == (lhs: DockerContainer, rhs: DockerContainer) -> Bool {
		return lhs.id == rhs.id && lhs.imageName == rhs.imageName && lhs.name == rhs.name && lhs.state == rhs.state
	}
}
