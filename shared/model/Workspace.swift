//
//  Workspace.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import SwiftyJSON

///posted to defaultCenter when a change happens to a member of the files array. userInfo["change"] is a WorkspaceFileChange notification
let WorkspaceFileChangedNotification = "WorkspaceFileChangedNotification"

class WorkspaceFileChange: NSObject {
	///Set means the entire array changed. This should never happen
	enum ChangeType { case Set, Insert, Remove,  Change }
	let changeType:ChangeType
	let oldFile:File?
	let newFile:File?
	let indexSet:NSIndexSet?
	init(old:File?, new:File?, type:ChangeType, indexes:NSIndexSet?) {
		self.changeType = type
		self.oldFile = old
		self.newFile = new
		self.indexSet = indexes
	}
	init(change:[String:AnyObject]?) {
		guard let ctype = change![NSKeyValueChangeKindKey] else {
			log.error("failed to cast change type")
			fatalError("bad type")
		}
		switch(UInt(ctype as! Int)) {
			case NSKeyValueChange.Insertion.rawValue:
				self.changeType = .Insert
			case NSKeyValueChange.Removal.rawValue:
				self.changeType = .Remove
			case NSKeyValueChange.Replacement.rawValue:
				self.changeType = .Change
			case NSKeyValueChange.Setting.rawValue:
				self.changeType = .Set
				log.warning("should never get a set message for fileArray property")
			default:
				fatalError("unknown kvo change type")
		}
		self.newFile = change![NSKeyValueChangeNewKey] as? File
		self.oldFile = change![NSKeyValueChangeOldKey] as? File
		self.indexSet = change![NSKeyValueChangeIndexesKey] as? NSIndexSet
	}
}

private var fileKvoKey:UInt8 = 0

public class Workspace: NSObject {
	let wspaceId : Int32
	let projectId : Int32
	let name : String
	let version : Int32
	///have to use a dynamic NSMutableArray so KVO via mutableArrayValueForKey will work properly
	private let filesArray : NSMutableArray = NSMutableArray() //can use kvo to monitor changes to contents
	///properly casts the fileArray as native swift array of File objects so swift code can ignore the fact that it is really a NSMutableArray set up for KVO
	var files:[File] { return filesArray as AnyObject as! [File] }
	///weak reference to parent project
	private(set) weak var project:Project?
	
	static func workspacesFromJsonArray(jsonArray : AnyObject, project:Project) -> [Workspace] {
		let array = JSON(jsonArray)
		return workspacesFromJsonArray(array, project: project)
	}

	static func workspacesFromJsonArray(json : JSON, project:Project) -> [Workspace] {
		var wspaces = [Workspace]()
		for (_,subJson):(String, JSON) in json {
			wspaces.append(Workspace(json:subJson, project: project))
		}
		wspaces.sortInPlace { return $0.name.localizedCompare($1.name) == .OrderedAscending }
		return wspaces
	}
	
	convenience init (jsonData:AnyObject, project:Project) {
		let json = JSON(jsonData)
		self.init(json: json, project: project)
	}
	
	init(json:JSON, project:Project) {
		self.project = project
		wspaceId = json["id"].int32Value
		projectId = json["projectId"].int32Value
		version = json["version"].int32Value
		name = json["name"].stringValue
		filesArray.addObjectsFromArray(File.filesFromJsonArray(json["files"]))
		super.init()
	}
	
	var fileCount:Int { return filesArray.count }
	
	public func fileWithId(fileId:Int) -> File? {
		let idx = indexOfFilePassingTest() { (obj, curIdx, _) in (obj as! File).fileId == fileId }
		if idx == NSNotFound { return nil }
		return file(at:idx)
	}
	
	public func file(at index:Int) -> File? {
		return filesArray.objectAtIndex(index) as? File
	}
	
	public func indexOfFile(file:File) -> Int? {
		return files.indexOf(file)
	}
	
	public func insertFile(aFile:AnyObject, at index:Int) {
		filesArray.insertObject(aFile, atIndex: index)
		let oldFile = filesArray.objectAtIndex(index) as! File
		let change = WorkspaceFileChange(old: oldFile, new: nil, type: .Insert, indexes: NSIndexSet(index: index))
		NSNotificationCenter.defaultCenter().postNotificationNameOnMainThread(WorkspaceFileChangedNotification, object: self, userInfo: ["change":change])
	}
	
	public func removeFile(at index:Int) {
		let oldFile = filesArray.objectAtIndex(index) as! File
		filesArray.removeObjectAtIndex(index)
		let change = WorkspaceFileChange(old: oldFile, new: nil, type: .Remove, indexes: NSIndexSet(index: index))
		NSNotificationCenter.defaultCenter().postNotificationNameOnMainThread(WorkspaceFileChangedNotification, object: self, userInfo: ["change":change])
	}
	
	public func replaceFile(at index:Int, withFile newFile:File) {
		let oldFile = filesArray.objectAtIndex(index) as! File
		assert(oldFile.fileId == newFile.fileId)
		filesArray.replaceObjectAtIndex(index, withObject: newFile)
		let change = WorkspaceFileChange(old: oldFile, new: newFile, type: .Change, indexes: NSIndexSet(index: index))
		NSNotificationCenter.defaultCenter().postAsyncNotificationNameOnMainThread(WorkspaceFileChangedNotification, object: self, userInfo: ["change":change])
	}
	
	public func indexOfFilePassingTest(predicate:(AnyObject, Int, UnsafeMutablePointer<ObjCBool>) -> Bool) -> Int {
		return filesArray.indexOfObjectPassingTest(predicate)
	}
	
	public override var description : String {
		return "<Workspace: \(name) (\(wspaceId))";
	}
	
}

public func ==(a: Workspace, b: Workspace) -> Bool {
	return a.wspaceId == b.wspaceId && a.version == b.version;
}
