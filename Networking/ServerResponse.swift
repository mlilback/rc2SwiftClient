//
//  ServerResponse.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Freddy
import os
import SwiftyUserDefaults

// MARK: Keys for UserDefaults
extension DefaultsKeys {
	static let nextBatchId = DefaultsKey<Int>("NextBatchIdKey")
}

/// operations that can be performed on the server
public enum FileOperation: String {
	case Remove = "rm", Rename = "rename", Duplicate = "duplicate"
}

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
		guard let msg = try? jsonObj.getString(at: "msg") else {
			os_log("failed to parse 'msg' from server response")
			return nil
		}
		let queryId = jsonObj.getOptionalInt(at: "queryId") ?? 0
		switch msg {
			case "results":
				guard let imagesJson = try? jsonObj.getArray(at: "images") else {
					return ServerResponse.results(queryId: queryId, text: jsonObj.getOptionalString(at: "string", or: ""))
				}
				//we override batchId because it is per-session, we need it unique across sessions
				let batchId = max(UserDefaults.standard[.nextBatchId], 1)
				let images = imagesJson.flatMap({ try? SessionImage($0, batchId: batchId) })
				UserDefaults.standard[.nextBatchId] = batchId + 1
				return ServerResponse.execComplete(queryId: queryId, batchId: jsonObj.getOptionalInt(at: "imageBatchId", or: -1), images: images)
			case "showOutput":
				guard let sfile: File = try? jsonObj.decode(at: "file") else {
					os_log("failed to decode file parameter to showOutput response")
					return nil
				}
				return ServerResponse.showOutput(queryId: queryId, updatedFile: sfile)
			case "error":
				return ServerResponse.error(queryId: queryId, error: jsonObj.getOptionalString(at: "error", or: "unknown error"))
			case "echo":
				guard let fileId = try? jsonObj.getInt(at: "fileId"), let query = try? jsonObj.getString(at: "query") else {
					os_log("failed to parse echo response")
					return nil
				}
				return ServerResponse.echoQuery(queryId: queryId, fileId: fileId, query: query)
			case "filechanged":
				guard let ftype = try? jsonObj.getString(at: "type"), let file: File = try? jsonObj.decode(at: "file") else {
					os_log("failed to parse filechanged response")
					return nil
				}
				return ServerResponse.fileChanged(changeType: ftype, file: file)
			case "variables":
				return parseVariables(jsonObj: jsonObj)
			case "saveResponse":
				//TODO: not looking at "success" and handling "error"
				return ServerResponse.saveResponse(transId: jsonObj.getOptionalString(at: "transId", or: ""))
			case "userid":
				return nil //TODO: need to implement
			case "fileOpResponse":
				guard let transId = try? jsonObj.getString(at: "transId"),
					let opName = try? jsonObj.getString(at: "operation"),
					let op = FileOperation(rawValue: opName),
					let file: File = try? jsonObj.decode(at: "file") else
				{
					return nil
				}
				return ServerResponse.fileOperationResponse(transId: transId, operation: op, file: file)
			default:
				os_log("unknown message from server:%{public}s", msg)
				return nil
		}
	}
	
	static func parseVariables(jsonObj: JSON) -> ServerResponse? {
		guard jsonObj.getOptionalBool(at: "delta") else {
			guard let vars: [Variable] = try? jsonObj.getArray(at: "variables").map({ try Variable.variableForJson($0) }) else {
				os_log("failed to parse variables from response")
				return nil
			}
			return ServerResponse.variables(single: jsonObj.getOptionalBool(at: "single"), variables: vars)
		}
		//TODO: server results changed, no longer sends assigned and removed arrays
		os_log("ignoring non-delta variable changes")
		return nil
//		let assigned = Variable.variablesForJsonDictionary(jsonObj["variables"]["assigned"].dictionaryValue)
//		let removed = jsonObj.getDictionary(at: "variables").dictionaryValue["assigned"]?.arrayValue.map() { $0.stringValue } ?? []
//		return ServerResponse.variablesDelta(assigned: assigned, removed: removed)
	}
}

public func == (a: ServerResponse, b: ServerResponse) -> Bool {
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
	
	init(_ jsonObj: JSON, batchId: Int = 0) throws {
		do {
			self.id = try jsonObj.getInt(at: "id")
			self.batchId = batchId == 0 ? try jsonObj.getInt(at: "batchId") : batchId
			self.name = try jsonObj.getString(at: "name")
			self.dateCreated = SessionImage.dateFormatter.date(from: try jsonObj.getString(at: "dateCreated"))
			self.imageData = Data(base64Encoded: try jsonObj.getString(at: "imageData"))
		} catch {
			os_log("error decoding SessionImage from json")
			throw error
		}
	}
	
	fileprivate init(imgId: Int, batchId: Int, name: String, date: Date) {
		self.id = imgId
		self.batchId = batchId
		self.name = name
		self.dateCreated = date
		self.imageData = nil
	}
	
	public required init?(coder decoder: NSCoder) {
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
