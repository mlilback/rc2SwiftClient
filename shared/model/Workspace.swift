//
//  Workspace.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import SwiftyJSON

///posted to defaultCenter when a change happens to a member of the files array.
let WorkspaceFileChangedNotification = "WorkspaceFileChangedNotification"

class WorkspaceFileChange: NSObject {
	///Set means the entire array changed. This should never happen
	enum ChangeType { case Set, Insert, Remove,  Change }
	let changeType:ChangeType
	let oldFile:File?
	let newFile:File?
	let indexSet:NSIndexSet?
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
	let userId : Int32
	let name : String
	let version : Int32
	///have to use a dynamic NSMutableArray so KVO via mutableArrayValueForKey will work properly
	dynamic let filesArray : NSMutableArray = NSMutableArray() //can use kvo to monitor changes to contents
	///properly casts the fileArray as native swift array of File objects so swift code can ignore the fact that it is really a NSMutableArray set up for KVO
	var files:[File] { return filesArray as AnyObject as! [File] }
	
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
	
	convenience init (jsonData:AnyObject) {
		let json = JSON(jsonData)
		self.init(json: json)
	}
	
	init(json:JSON) {
		wspaceId = json["id"].int32Value
		userId = json["userId"].int32Value
		version = json["version"].int32Value
		name = json["name"].stringValue
		filesArray.addObjectsFromArray(File.filesFromJsonArray(json["files"]))
		super.init()
		addObserver(self, forKeyPath: "fileArray", options: [.New,.Old], context:&fileKvoKey)
	}
	
	deinit {
		removeObserver(self, forKeyPath: "fileArray", context:&fileKvoKey)
	}
	
	public func countOfFileArray() -> Int {
		return filesArray.count
	}
	
	public func objectInFileArrayAtIndex(index:Int) -> AnyObject? {
		return filesArray.objectAtIndex(index)
	}
	
	public func insertObject(aFile:AnyObject, inFileArrayAtIndex index:Int) {
		filesArray.insertObject(aFile, atIndex: index)
	}
	
	public func removeObjectFromFileArrayAtIndex(index:Int) {
		filesArray.removeObjectAtIndex(index)
	}
	
	public override var description : String {
		return "<Workspace: \(name) (\(wspaceId))";
	}
	
	override public func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>)
	{
		if context == &fileKvoKey {
			let fileChange = WorkspaceFileChange(change: change)
			NSNotificationCenter.defaultCenter().postNotificationNameOnMainThread(WorkspaceFileChangedNotification, object: self, userInfo: ["change":fileChange])
		} else {
			super.observeValueForKeyPath(keyPath, ofObject: object, change: change, context: context)
		}
	}

}

public func ==(a: Workspace, b: Workspace) -> Bool {
	return a.wspaceId == b.wspaceId && a.version == b.version;
}
