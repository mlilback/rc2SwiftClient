//
//  ServerResponse.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

public enum ServerResponse : Equatable {
	case Error(queryId:Int, error:String)
	case EchoQuery(queryId:Int, fileId:Int, query:String)
	case ExecComplete(queryId:Int, batchId:Int, images:[SessionImage])
	case Help(topic:String, paths:[HelpItem])
	case Results(queryId:Int, fileId:Int, text:String)
	case Variable(socketId:Int, delta:Bool, single:Bool, variables:Dictionary<String, JSON>)
	
	static func parseResponse(jsonObj:JSON) -> ServerResponse? {
		switch(jsonObj["msg"].stringValue) {
			case "results":
				if jsonObj["images"] != nil {
					let images = jsonObj["images"].arrayValue.map({ return SessionImage($0) })
					return ServerResponse.ExecComplete(queryId: jsonObj["queryId"].intValue, batchId: jsonObj["imageBatchId"].intValue, images: images)
			} else {
					return ServerResponse.Results(queryId: jsonObj["queryId"].intValue, fileId: jsonObj["fileId"].intValue, text: jsonObj["string"].stringValue)
			}
			case "error":
				return ServerResponse.Error(queryId: jsonObj["queryId"].intValue, error: jsonObj["error"].stringValue)
			case "echo":
				return ServerResponse.EchoQuery(queryId: jsonObj["queryId"].intValue, fileId: jsonObj["fileId"].intValue, query: jsonObj["query"].stringValue)
			case "help":
				return ServerResponse.Help(topic: jsonObj["topic"].stringValue, paths: jsonObj["paths"].arrayValue.map({ return HelpItem(dict: $0.dictionaryValue) }))
			case "variables":
				return ServerResponse.Variable(socketId: jsonObj["socketId"].intValue, delta: jsonObj["delta"].boolValue, single: jsonObj["singleValue"].boolValue, variables: jsonObj["variables"].dictionaryValue)
			default:
				return nil
		}
	}
}

public func == (a:ServerResponse, b:ServerResponse) -> Bool {
	switch (a, b) {
		case (.Error(let q1, let e1), .Error(let q2, let e2)):
			return q1 == q2 && e1 == e2
		case (.EchoQuery(let q1, let f1, let s1), .EchoQuery(let q2, let f2, let s2)):
			return q1 == q2 && f1 == f2 && s1 == s2
		case (.ExecComplete(let q1, let b1, let i1), .ExecComplete(let q2, let b2, let i2)):
			return q1 == q2 && b1 == b2 && i1 == i2
		case (.Help(let t1, let p1), .Help(let t2, let p2)):
			return t1 == t2 && p1 == p2
		case (.Results(let q1, let f1, let t1), .Results(let q2, let f2, let t2)):
			return q1 == q2 && f1 == f2 && t1 == t2
		case (.Variable(let s1, let d1, let sn1, let v1), .Variable(let s2, let d2, let sn2, let v2)):
			return s1 == s2 && d1 == d2 && sn1 == sn2 && v1 == v2
		default:
			return false
	}
}

public struct HelpItem : Equatable {
	let title : String
	let url : NSURL
	init(dict:Dictionary<String,JSON>) {
		title = (dict["title"]?.stringValue)!
		url = NSURL(string: (dict["url"]?.stringValue)!)!
	}
}

public func ==(a:HelpItem, b:HelpItem) -> Bool {
	return a.title == b.title && a.url == b.url
}

public class SessionImage: NSObject, NSSecureCoding, NSCopying {
	let id:Int
	let batchId:Int
	let name:String!
	let imageData:NSData?
	let dateCreated:NSDate!
	
	public static func supportsSecureCoding() -> Bool {
		return true
	}
	
	private static var dateFormatter:NSDateFormatter = {
		let formatter = NSDateFormatter()
		formatter.locale = NSLocale(localeIdentifier: "en_US_POSIX")
		formatter.dateFormat = "YYYY-MM-dd"
		return formatter
	}()
	
	init(_ jsonObj:JSON) {
		self.id = jsonObj["id"].intValue
		self.batchId = jsonObj["batchId"].intValue
		self.name = jsonObj["name"].stringValue
		self.dateCreated = SessionImage.dateFormatter.dateFromString(jsonObj["dateCreated"].stringValue)!
		self.imageData = NSData(base64EncodedString: jsonObj["imageData"].stringValue, options: [])!
	}
	
	private init(imgId:Int, batchId:Int, name:String, date:NSDate) {
		self.id = imgId
		self.batchId = batchId
		self.name = name
		self.dateCreated = date
		self.imageData = nil
	}
	
	public required init?(coder decoder:NSCoder) {
		self.id = decoder.decodeIntegerForKey("imageId")
		self.batchId = decoder.decodeIntegerForKey("batchId")
		self.name = decoder.decodeObjectOfClass(NSString.self, forKey: "name") as String?
		self.dateCreated = decoder.decodeObjectOfClass(NSDate.self, forKey: "dateCreated") as NSDate?
		self.imageData = nil
		super.init()
		if (name.isEmpty || dateCreated == nil) { return nil }
	}
	
	public func encodeWithCoder(coder: NSCoder) {
		coder.encodeInteger(self.id, forKey: "imageId")
		coder.encodeInteger(self.batchId, forKey: "batchId")
		coder.encodeObject(self.name, forKey: "name")
		coder.encodeObject(self.dateCreated, forKey: "dateCreated")
	}
	
	public func copyWithZone(zone: NSZone) -> AnyObject {
		return SessionImage(imgId: id, batchId: batchId, name:name, date: dateCreated)
	}
}

public func ==(a:SessionImage, b:SessionImage) -> Bool {
	return a.id == b.id 
}

