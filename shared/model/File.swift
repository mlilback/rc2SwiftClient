//
//  File.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

public class File: CustomStringConvertible, Equatable {
	let fileId : Int32
	let name : String
	let version : Int32
	let fileSize : Int32
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
		fileId = json["id"].int32Value
		name = json["name"].stringValue
		version = json["version"].int32Value
		fileSize = json["fileSize"].int32Value
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
	
	public var description : String {
		return "<File: \(name) (\(fileId))";
	}

}

public func ==(a: File, b: File) -> Bool {
	return a.fileId == b.fileId && a.version == b.version;
}
