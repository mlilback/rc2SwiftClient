//
//  ServerResponse.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import SwiftyJSON

public enum ServerResponse : Equatable {
	case Error(queryId:Int, error:String)
	case EchoQuery(queryId:Int, fileId:Int, query:String)
	case ExecComplete(queryId:Int, batchId:Int, images:[SessionImage])
	case FileChanged(changeType:String, file:File)
	case Help(topic:String, paths:[HelpItem])
	case Results(queryId:Int, text:String)
	case SaveResponse(transId:String)
	case ShowOutput(queryId:Int, updatedFile:File)
	case Variables(socketId:Int, single:Bool, variables:[Variable])
	case VariablesDelta(socketId:Int, assigned:[Variable], removed:[String])
	
	
	func isEcho() -> Bool {
		if case .EchoQuery(_, _, _) = self { return true }
		return false
	}
	
	static func parseResponse(jsonObj:JSON) -> ServerResponse? {
		switch(jsonObj["msg"].stringValue) {
			case "results":
				if jsonObj["images"] != nil {
					//we override batchId because it is per-session, we need it unique across sessions
					let batchId = max(NSUserDefaults.standardUserDefaults().integerForKey("NextBatchIdKey"), 1)
					let images = jsonObj["images"].arrayValue.map({ return SessionImage($0, batchId:batchId) })
					NSUserDefaults.standardUserDefaults().setInteger(batchId+1, forKey: "NextBatchIdKey")
					return ServerResponse.ExecComplete(queryId: jsonObj["queryId"].intValue, batchId: jsonObj["imageBatchId"].intValue, images: images)
				} else {
					return ServerResponse.Results(queryId: jsonObj["queryId"].intValue, text: jsonObj["string"].stringValue)
				}
			case "showOutput":
				return ServerResponse.ShowOutput(queryId: jsonObj["queryId"].intValue, updatedFile: File(json: jsonObj["file"]))
			case "error":
				return ServerResponse.Error(queryId: jsonObj["queryId"].intValue, error: jsonObj["error"].stringValue)
			case "echo":
				return ServerResponse.EchoQuery(queryId: jsonObj["queryId"].intValue, fileId: jsonObj["fileId"].intValue, query: jsonObj["query"].stringValue)
			case "filechanged":
				return ServerResponse.FileChanged(changeType: jsonObj["type"].stringValue, file: File(json: jsonObj["file"]))
			case "help":
				return ServerResponse.Help(topic: jsonObj["topic"].stringValue, paths: jsonObj["paths"].arrayValue.map({ return HelpItem(dict: $0.dictionaryValue) }))
			case "variables":
				let sid = jsonObj["socketId"].intValue
				if jsonObj["delta"].boolValue {
					let assigned = Variable.variablesForJsonDictionary(jsonObj["variables"]["assigned"].dictionaryValue)
					let removed = jsonObj["variables"].dictionaryValue["assigned"]?.arrayValue.map() { $0.stringValue } ?? []
					return ServerResponse.VariablesDelta(socketId: sid, assigned: assigned, removed: removed)
				}
				return ServerResponse.Variables(socketId: sid, single: jsonObj["single"].boolValue, variables: Variable.variablesForJsonDictionary(jsonObj["variables"].dictionaryValue))
			case "saveResponse":
				return ServerResponse.SaveResponse(transId: jsonObj["transId"].stringValue)
			case "userid":
				return nil //TODO: need to implement
			default:
				log.warning("unknown message from server:\(jsonObj["msg"].stringValue)")
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
		case (.Results(let q1, let t1), .Results(let q2, let t2)):
			return q1 == q2 && t1 == t2
		case (.Variables(let s1, let sn1, let v1), .Variables(let s2, let sn2, let v2)):
			return s1 == s2 && sn1 == sn2 && v1 == v2
		case (.VariablesDelta(let s1, let a1, let r1), .VariablesDelta(let s2, let a2, let r2)):
			return s1 == s2 && r1 == r2 && a1 == a2
		case (.ShowOutput(let q1, let f1), .ShowOutput(let q2, let f2)):
			return q1 == q2 && f1.fileId == f2.fileId && f1.version == f2.version
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
	
	init(_ jsonObj:JSON, batchId:Int = 0) {
		self.id = jsonObj["id"].intValue
		self.batchId = batchId == 0 ? jsonObj["batchId"].intValue : batchId
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
	
	public override func isEqual(object: AnyObject?) -> Bool {
		if let other = object as? SessionImage {
			return self.id == other.id && self.batchId == other.batchId && self.name == other.name && self.dateCreated == other.dateCreated
		}
		return false
	}
}

public func ==(a:SessionImage, b:SessionImage) -> Bool {
	return a.id == b.id 
}
