//
//  Project.swift
//  SwiftClient
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import SwiftyJSON

public class Project: NSObject {
	let projectId : Int32
	let userId : Int32
	let name : String
	let version : Int32
	///have to use a dynamic NSMutableArray so KVO via mutableArrayValueForKey will work properly
	private let wspaceArray : NSMutableArray = NSMutableArray() //can use kvo to monitor changes to contents
	///properly casts the wspaceArray as native swift array of Workspace objects so swift code can ignore the fact that it is really a NSMutableArray set up for KVO
	var workspaces:[Workspace] { return wspaceArray as AnyObject as! [Workspace] }
	
	static func projectsFromJsonArray(jsonArray : AnyObject) -> [Project] {
		let array = JSON(jsonArray)
		return projectsFromJsonArray(array)
	}
	
	static func projectsFromJsonArray(json : JSON) -> [Project] {
		var projects = [Project]()
		for (_,subJson):(String, JSON) in json {
			projects.append(Project(json:subJson))
		}
		projects.sortInPlace { return $0.name.localizedCompare($1.name) == .OrderedAscending }
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
		wspaceArray.addObjectsFromArray(Workspace.workspacesFromJsonArray(json["workspaces"], project:self))
	}
	
	var workspaceCount:Int { return wspaceArray.count }
	
	public func workspaceWithId(projectId:Int) -> Workspace? {
		let pid = Int32(projectId)
		let idx = indexOfWorkspacePassingTest() { (obj, curIdx, _) in (obj as! Workspace).projectId == pid }
		if idx == NSNotFound { return nil }
		return wspace(at:idx)
	}
	
	public func workspaceWithName(wspaceName:String) -> Workspace? {
		let idx = indexOfWorkspacePassingTest() { (obj, curIdx, _) in (obj as! Workspace).name == wspaceName }
		if idx == NSNotFound { return nil }
		return wspace(at:idx)
	}
	
	public func wspace(at index:Int) -> Workspace? {
		return wspaceArray.objectAtIndex(index) as? Workspace
	}
	
	public func indexOfWorkspace(wspace:Workspace) -> Int? {
		return workspaces.indexOf(wspace)
	}
	
	public func insertWorkspace(aWorkspace:AnyObject, at index:Int) {
		wspaceArray.insertObject(aWorkspace, atIndex: index)
	}
	
	public func removeWorkspace(at index:Int) {
		wspaceArray.removeObjectAtIndex(index)
	}
	
	public func indexOfWorkspacePassingTest(predicate:(AnyObject, Int, UnsafeMutablePointer<ObjCBool>) -> Bool) -> Int {
		return wspaceArray.indexOfObjectPassingTest(predicate)
	}
	
	public override var description : String {
		return "<Project: \(name) (\(projectId))";
	}
	
}

public func ==(a: Project, b: Project) -> Bool {
	return a.projectId == b.projectId && a.version == b.version;
}
