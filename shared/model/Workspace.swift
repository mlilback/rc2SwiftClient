//
//  Workspace.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import SwiftyJSON
import os

///posted to defaultCenter when a change happens to a member of the files array. userInfo["change"] is a WorkspaceFileChange notification
let WorkspaceFileChangedNotification = NSNotification.Name(rawValue: "WorkspaceFileChangedNotification")

class WorkspaceFileChange: NSObject {
	///Set means the entire array changed. This should never happen
	enum ChangeType { case set, insert, remove,  change }
	let changeType:ChangeType
	let oldFile:File?
	let newFile:File?
	let indexSet:IndexSet?
	init(old:File?, new:File?, type:ChangeType, indexes:IndexSet?) {
		self.changeType = type
		self.oldFile = old
		self.newFile = new
		self.indexSet = indexes
	}
	init(change:NSDictionary?) {
		guard let ctype = change?.object(forKey: [NSKeyValueChangeKey.kindKey]) else {
			os_log("failed to cast change type", type:.error)
			fatalError("bad type")
		}
		switch(UInt(ctype as! Int)) {
			case NSKeyValueChange.insertion.rawValue:
				self.changeType = .insert
			case NSKeyValueChange.removal.rawValue:
				self.changeType = .remove
			case NSKeyValueChange.replacement.rawValue:
				self.changeType = .change
			case NSKeyValueChange.setting.rawValue:
				self.changeType = .set
				os_log("should never get a set message for fileArray property")
			default:
				fatalError("unknown kvo change type")
		}
		self.newFile = change![NSKeyValueChangeKey.newKey] as? File
		self.oldFile = change![NSKeyValueChangeKey.oldKey] as? File
		self.indexSet = change![NSKeyValueChangeKey.indexesKey] as? IndexSet
	}
}

private var fileKvoKey:UInt8 = 0

open class Workspace: NSObject {
	let wspaceId : Int32
	let projectId : Int32
	let name : String
	let version : Int32
	///have to use a dynamic NSMutableArray so KVO via mutableArrayValueForKey will work properly
	fileprivate let filesArray : NSMutableArray = NSMutableArray() //can use kvo to monitor changes to contents
	///properly casts the fileArray as native swift array of File objects so swift code can ignore the fact that it is really a NSMutableArray set up for KVO
	var files:[File] { return filesArray as AnyObject as! [File] }
	///weak reference to parent project
	fileprivate(set) weak var project:Project?
	
	static func workspacesFromJsonArray(_ jsonArray : AnyObject, project:Project) -> [Workspace] {
		let array = JSON(jsonArray)
		return workspacesFromJsonArray(array, project: project)
	}

	static func workspacesFromJsonArray(_ json : JSON, project:Project) -> [Workspace] {
		var wspaces = [Workspace]()
		for (_,subJson):(String, JSON) in json {
			wspaces.append(Workspace(json:subJson, project: project))
		}
		wspaces.sort { return $0.name.localizedCompare($1.name) == .orderedAscending }
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
		filesArray.addObjects(from: File.filesFromJsonArray(json["files"]))
		super.init()
	}
	
	var fileCount:Int { return filesArray.count }
	
	open func fileWithId(_ fileId:Int) -> File? {
		guard let idx = indexOfFilePassingTest({ $0.fileId == fileId }) else { return nil }
		return file(at:idx)
	}
	
	open func file(at index:Int) -> File? {
		return filesArray.object(at: index) as? File
	}
	
	open func indexOfFile(_ file:File) -> Int? {
		return files.index(of: file)
	}
	
	open func insertFile(_ aFile:AnyObject, at index:Int) {
		filesArray.insert(aFile, at: index)
		let oldFile = filesArray.object(at: index) as! File
		let change = WorkspaceFileChange(old: oldFile, new: nil, type: .insert, indexes: IndexSet(integer: index))
		NotificationCenter.default.postNotificationNameOnMainThread(WorkspaceFileChangedNotification.rawValue, object: self, userInfo: ["change":change])
	}
	
	open func removeFile(at index:Int) {
		let oldFile = filesArray.object(at: index) as! File
		filesArray.removeObject(at: index)
		let change = WorkspaceFileChange(old: oldFile, new: nil, type: .remove, indexes: IndexSet(integer: index))
		NotificationCenter.default.postNotificationNameOnMainThread(WorkspaceFileChangedNotification.rawValue, object: self, userInfo: ["change":change])
	}
	
	open func replaceFile(at index:Int, withFile newFile:File) {
		let oldFile = filesArray.object(at: index) as! File
		assert(oldFile.fileId == newFile.fileId)
		filesArray.replaceObject(at: index, with: newFile)
		let change = WorkspaceFileChange(old: oldFile, new: newFile, type: .change, indexes: IndexSet(integer: index))
		NotificationCenter.default.postAsyncNotificationNameOnMainThread(WorkspaceFileChangedNotification.rawValue, object: self, userInfo: ["change":change])
	}
	
	open func indexOfFilePassingTest(_ predicate:(File) -> Bool) -> Int? {
		return files.index(where: predicate)
	}
	
	open override var description : String {
		return "<Workspace: \(name) (\(wspaceId))";
	}
	
}

public func ==(a: Workspace, b: Workspace) -> Bool {
	return a.wspaceId == b.wspaceId && a.version == b.version;
}
