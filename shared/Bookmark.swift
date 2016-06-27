//
//  Bookmark.swift
//  SwiftClient
//
//  Created by Mark Lilback on 6/27/16.
//  Copyright © 2016 Rc2. All rights reserved.
//

import Foundation
import SwiftyJSON

/// represents a bookmark to an rc2 server
public struct Bookmark: JSONSerializable, CustomStringConvertible, Equatable {
	let name:String
	let host:String
	let port:Int
	let user:String
	let projectName:String
	let workspaceName:String?
	let isSecure:Bool
	
	init(name:String, host:String, port:Int, user:String, project:String, workspace:String?, secure:Bool = false) {
		self.name = name
		self.host = host
		self.port = port
		self.user = user
		self.projectName = project
		self.workspaceName = workspace
		self.isSecure = secure
	}
	
	init?(json:JSON) {
		do {
			let dict = try JSONDserializer.deserialize(json)
			self.name = dict["name"] as! String
			self.host = dict["host"] as! String
			self.port = dict["port"] as! Int
			self.user = dict["user"] as! String
			self.projectName = dict["projectName"] as! String
			self.workspaceName = dict["workspaceName"] as? String
			self.isSecure = dict["isSecure"] as! Bool
		} catch _ {
			return nil
		}
	}
	
	public var description:String { return "<Bookmark: \(name)" }
}

public func ==(lhs:Bookmark, rhs:Bookmark) -> Bool {
	return lhs.name == rhs.name && lhs.host == rhs.host && lhs.port == rhs.port && lhs.projectName == rhs.projectName && lhs.workspaceName == rhs.workspaceName
}
