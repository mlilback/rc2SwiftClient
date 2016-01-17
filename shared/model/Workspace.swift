//
//  Workspace.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import SwiftyJSON

public struct Workspace: CustomStringConvertible, Equatable {
	let wspaceId : Int32
	let userId : Int32
	let name : String
	let version : Int32
	let files : [File]
	
	static func workspacesFromJsonArray(jsonArray : AnyObject) -> [Workspace] {
		let array = JSON(jsonArray)
		return workspacesFromJsonArray(array)
	}

	static func workspacesFromJsonArray(json : JSON) -> [Workspace] {
		var wspaces = [Workspace]()
		for (_,subJson):(String, JSON) in json {
			wspaces.append(Workspace(json:subJson))
		}
		wspaces.sortInPlace { return $0.name.localizedCompare($1.name) == .OrderedAscending }
		return wspaces
	}
	
	init (jsonData:AnyObject) {
		let json = JSON(jsonData)
		self.init(json: json)
	}
	
	init(json:JSON) {
		wspaceId = json["id"].int32Value
		userId = json["userId"].int32Value
		version = json["version"].int32Value
		name = json["name"].stringValue
		files = File.filesFromJsonArray(json["files"])
	}
	
	public var description : String {
		return "<Workspace: \(name) (\(wspaceId))";
	}

}

public func ==(a: Workspace, b: Workspace) -> Bool {
	return a.wspaceId == b.wspaceId && a.version == b.version;
}
