//
//  ServerResponse.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import SwiftyJSON
import os

public enum ServerResponse : Equatable {
	case error(queryId:Int, error:String)
	case echoQuery(queryId:Int, fileId:Int, query:String)
	case execComplete(queryId:Int, batchId:Int, images:[SessionImage])
	case fileChanged(changeType:String, file:File)
	case results(queryId:Int, text:String)
	case saveResponse(transId:String)
	case showOutput(queryId:Int, updatedFile:File)
	case variables(single:Bool, variables:[Variable])
	case variablesDelta(assigned:[Variable], removed:[String])
	case fileOperationResponse(transId:String, operation:FileOperation, file:File)
	
	
	func isEcho() -> Bool {
		if case .echoQuery(_, _, _) = self { return true }
		return false
	}
	
	static func parseResponse(_ jsonObj:JSON) -> ServerResponse? {
		switch(jsonObj["msg"].stringValue) {
			case "results":
				if jsonObj["images"] != nil {
					//we override batchId because it is per-session, we need it unique across sessions
					let batchId = max(UserDefaults.standard.integer(forKey: "NextBatchIdKey"), 1)
					let images = jsonObj["images"].arrayValue.map({ return SessionImage($0, batchId:batchId) })
					UserDefaults.standard.set(batchId+1, forKey: "NextBatchIdKey")
					return ServerResponse.execComplete(queryId: jsonObj["queryId"].intValue, batchId: jsonObj["imageBatchId"].intValue, images: images)
				} else {
					return ServerResponse.results(queryId: jsonObj["queryId"].intValue, text: jsonObj["string"].stringValue)
				}
			case "showOutput":
				return ServerResponse.showOutput(queryId: jsonObj["queryId"].intValue, updatedFile: File(json: jsonObj["file"]))
			case "error":
				return ServerResponse.error(queryId: jsonObj["queryId"].intValue, error: jsonObj["error"].stringValue)
			case "echo":
				return ServerResponse.echoQuery(queryId: jsonObj["queryId"].intValue, fileId: jsonObj["fileId"].intValue, query: jsonObj["query"].stringValue)
			case "filechanged":
				return ServerResponse.fileChanged(changeType: jsonObj["type"].stringValue, file: File(json: jsonObj["file"]))
			case "variables":
				if jsonObj["delta"].boolValue {
					let assigned = Variable.variablesForJsonDictionary(jsonObj["variables"]["assigned"].dictionaryValue)
					let removed = jsonObj["variables"].dictionaryValue["assigned"]?.arrayValue.map() { $0.stringValue } ?? []
					return ServerResponse.variablesDelta(assigned: assigned, removed: removed)
				}
				return ServerResponse.variables(single: jsonObj["single"].boolValue, variables: Variable.variablesForJsonDictionary(jsonObj["variables"].dictionary))
			case "saveResponse":
				//TODO: not looking at "success" and handling "error"
				return ServerResponse.saveResponse(transId: jsonObj["transId"].stringValue)
			case "userid":
				return nil //TODO: need to implement
			case "fileOpResponse":
				return ServerResponse.fileOperationResponse(transId: jsonObj["transId"].stringValue, operation: FileOperation(rawValue:jsonObj["operation"].stringValue)!, file: File(json: jsonObj["file"]))
			default:
				os_log("unknown message from server:%@", jsonObj["msg"].stringValue)
				return nil
		}
	}
}

public func == (a:ServerResponse, b:ServerResponse) -> Bool {
	switch (a, b) {
		case (.error(let q1, let e1), .error(let q2, let e2)):
			return q1 == q2 && e1 == e2
		case (.echoQuery(let q1, let f1, let s1), .echoQuery(let q2, let f2, let s2)):
			return q1 == q2 && f1 == f2 && s1 == s2
		case (.execComplete(let q1, let b1, let i1), .execComplete(let q2, let b2, let i2)):
			return q1 == q2 && b1 == b2 && i1 == i2
		case (.results(let q1, let t1), .results(let q2, let t2)):
			return q1 == q2 && t1 == t2
		case (.variables(let sn1, let v1), .variables(let sn2, let v2)):
			return sn1 == sn2 && v1 == v2
		case (.variablesDelta(let a1, let r1), .variablesDelta(let a2, let r2)):
			return r1 == r2 && a1 == a2
		case (.showOutput(let q1, let f1), .showOutput(let q2, let f2)):
			return q1 == q2 && f1.fileId == f2.fileId && f1.version == f2.version
		default:
			return false
	}
}

public struct HelpItem : Equatable {
	let title : String
	let url : URL
	init(dict:Dictionary<String,JSON>) {
		title = (dict["title"]?.stringValue)!
		url = NSURL(string: (dict["url"]?.stringValue)!)! as URL
	}
}

public func ==(a:HelpItem, b:HelpItem) -> Bool {
	return a.title == b.title && a.url == b.url
}

///an immutable class representing an image stored on the server and serializable for local caching
open class SessionImage: NSObject, NSSecureCoding, NSCopying {
	let id:Int
	let batchId:Int
	let name:String!
	let imageData:Data?
	let dateCreated:Date!
	
	public static var supportsSecureCoding : Bool {
		return true
	}
	
	fileprivate static var dateFormatter:DateFormatter = {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.dateFormat = "YYYY-MM-dd"
		return formatter
	}()
	
	init(_ jsonObj:JSON, batchId:Int = 0) {
		self.id = jsonObj["id"].intValue
		self.batchId = batchId == 0 ? jsonObj["batchId"].intValue : batchId
		self.name = jsonObj["name"].stringValue
		self.dateCreated = SessionImage.dateFormatter.date(from: jsonObj["dateCreated"].stringValue)!
		self.imageData = NSData(base64Encoded: jsonObj["imageData"].stringValue, options: [])! as Data
	}
	
	fileprivate init(imgId:Int, batchId:Int, name:String, date:Date) {
		self.id = imgId
		self.batchId = batchId
		self.name = name
		self.dateCreated = date
		self.imageData = nil
	}
	
	public required init?(coder decoder:NSCoder) {
		self.id = decoder.decodeInteger(forKey: "imageId")
		self.batchId = decoder.decodeInteger(forKey: "batchId")
		self.name = decoder.decodeObject(of: NSString.self, forKey: "name") as String?
		self.dateCreated = decoder.decodeObject(of: NSDate.self, forKey: "dateCreated") as Date?
		self.imageData = nil
		super.init()
		if (name.isEmpty || dateCreated == nil) { return nil }
	}
	
	open func encode(with coder: NSCoder) {
		coder.encode(self.id, forKey: "imageId")
		coder.encode(self.batchId, forKey: "batchId")
		coder.encode(self.name, forKey: "name")
		coder.encode(self.dateCreated, forKey: "dateCreated")
	}
	
	open func copy(with zone: NSZone?) -> Any {
		return SessionImage(imgId: id, batchId: batchId, name:name, date: dateCreated)
	}
	
	open override func isEqual(_ object: Any?) -> Bool {
		if let other = object as? SessionImage {
			return self.id == other.id && self.batchId == other.batchId && self.name == other.name && self.dateCreated == other.dateCreated
		}
		return false
	}
}

public func ==(a:SessionImage, b:SessionImage) -> Bool {
	return a.id == b.id 
}
