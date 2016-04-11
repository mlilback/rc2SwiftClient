//
//  File.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import SwiftyJSON

public class File: CustomStringConvertible, Equatable {
	let fileId : Int
	let name : String
	let version : Int
	let fileSize : Int
	let dateCreated : NSDate
	let lastModified : NSDate
	let fileType: FileType
	
	static func filesFromJsonArray(jsonArray : AnyObject) -> [File] {
		let array = JSON(jsonArray)
		return filesFromJsonArray(array)
	}

	static func filesFromJsonArray(json : JSON) -> [File] {
		var array = [File]()
		for (_,subJson):(String, JSON) in json {
			array.append(File(json:subJson))
		}
		return array
	}

	convenience init (jsonData:AnyObject) {
		let json = JSON(jsonData)
		self.init(json: json)
	}
	
	init(json:JSON) {
		fileId = json["id"].intValue
		name = json["name"].stringValue
		version = json["version"].intValue
		fileSize = json["fileSize"].intValue
		dateCreated = NSDate(timeIntervalSince1970: json["dateCreated"].doubleValue/1000.0)
		lastModified = NSDate(timeIntervalSince1970: json["lastModified"].doubleValue/1000.0)
		if let ft = FileType.fileTypeWithExtension((name as NSString).pathExtension) {
			self.fileType = ft
		} else {
			assertionFailure("invalid file type")
			//compiler won't let the property not be set, even though we're exiting the program
			self.fileType = FileType.allFileTypes.first!
		}
	}
	
	///initialize with native dictionary from a MessagePackDictionary
	init(dict:[String:AnyObject]) {
		fileId = dict["id"] as! Int
		name = dict["name"] as! String
		version = dict["version"] as! Int
		fileSize = dict["fileSize"] as! Int!
		dateCreated = NSDate(timeIntervalSince1970: (dict["dateCreated"] as! Double)/1000.0)
		lastModified = NSDate(timeIntervalSince1970: (dict["lastModified"] as! Double)/1000.0)
		if let ft = FileType.fileTypeWithExtension((name as NSString).pathExtension) {
			self.fileType = ft
		} else {
			assertionFailure("invalid file type")
			//compiler won't let the property not be set, even though we're exiting the program
			self.fileType = FileType.allFileTypes.first!
		}
	}
	
	public var description : String {
		return "<File: \(name) (\(fileId) v\(version))>";
	}

}

public func ==(a: File, b: File) -> Bool {
	return a.fileId == b.fileId && a.version == b.version;
}
