//
//  Project.swift
//  SwiftClient
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import SwiftyJSON

open class Project: NSObject {
	let projectId : Int32
	let userId : Int32
	let name : String
	let version : Int32
	///have to use a dynamic NSMutableArray so KVO via mutableArrayValueForKey will work properly
	fileprivate let wspaceArray : NSMutableArray = NSMutableArray() //can use kvo to monitor changes to contents
	///properly casts the wspaceArray as native swift array of Workspace objects so swift code can ignore the fact that it is really a NSMutableArray set up for KVO
	var workspaces:[Workspace] { return wspaceArray as AnyObject as! [Workspace] }
	
	static func projectsFromJsonArray(_ jsonArray : AnyObject) -> [Project] {
		let array = JSON(jsonArray)
		return projectsFromJsonArray(array)
	}
	
	static func projectsFromJsonArray(_ json : JSON) -> [Project] {
		var projects = [Project]()
		for (_,subJson):(String, JSON) in json {
			projects.append(Project(json:subJson))
		}
		projects.sort { return $0.name.localizedCompare($1.name) == .orderedAscending }
		return projects
	}
	
	convenience init (jsonData:AnyObject) {
		let json = JSON(jsonData)
		self.init(json: json)
	}
	
	init(json:JSON) {
		projectId = json["id"].int32Value
		userId = json["userId"].int32Value
		version = json["version"].int32Value
		name = json["name"].stringValue
		super.init()
		wspaceArray.addObjects(from: Workspace.workspacesFromJsonArray(json["workspaces"], project:self))
	}
	
	var workspaceCount:Int { return wspaceArray.count }
	
	open func workspace(withProjectId projId: Int) -> Workspace? {
		let target = Int32(projId)
		if let idx = workspaces.index(where: { $0.projectId == target }) {
			return workspaces[idx]
		}
		return nil
	}
	
	open func workspace(withName wspaceName:String) -> Workspace? {
		if let idx = workspaces.index(where: { $0.name == wspaceName }) {
			return workspaces[idx]
		}
		return nil
	}
	
	open func workspace(at index:Int) -> Workspace? {
		return wspaceArray.object(at: index) as? Workspace
	}
	
	open func indexOfWorkspace(_ wspace:Workspace) -> Int? {
		return workspaces.index(of: wspace)
	}
	
	open func insertWorkspace(_ aWorkspace:AnyObject, at index:Int) {
		wspaceArray.insert(aWorkspace, at: index)
	}
	
	open func removeWorkspace(at index:Int) {
		wspaceArray.removeObject(at: index)
	}
	
	open func indexOfWorkspace(passingTest: (Workspace) -> Bool) -> Int? {
		return workspaces.index(where: passingTest)
	}
	
	open override var description : String {
		return "<Project: \(name) (\(projectId))";
	}
	
}

public func ==(a: Project, b: Project) -> Bool {
	return a.projectId == b.projectId && a.version == b.version;
}
