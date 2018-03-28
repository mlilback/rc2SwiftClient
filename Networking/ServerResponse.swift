//
//  ServerResponse.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Freddy
import MJLLogger
import SwiftyUserDefaults
import Result
import Rc2Common
import Model

// MARK: Keys for UserDefaults
extension DefaultsKeys {
	static let nextBatchId = DefaultsKey<Int>("NextBatchIdKey")
}

/// operations that can be performed on the server
public enum FileOperation: String {
	case Remove = "rm", Rename = "rename", Duplicate = "duplicate"
}

public enum ServerResponse: Equatable {
	case error(queryId: Int, error: String)
	case echoQuery(queryId: Int, fileId: Int, query: String)
	case execComplete(queryId: Int, batchId: Int, images: [SessionImage])
	case results(queryId: Int, text: String)
	case saveResponse(transId: String)
	case fileChanged(changeType: String, fileId: Int, file: AppFile?)
	case showOutput(queryId: Int, updatedFile: AppFile)
	case variables(single: Bool, variables: [Variable])
	case variablesDelta(assigned: [Variable], removed: [String])
	case fileOperationResponse(transId: String, operation: FileOperation, result: Result<AppFile?, Rc2Error>)
	
	public func isEcho() -> Bool {
		if case .echoQuery(_, _, _) = self { return true }
		return false
	}
	
	// swiftlint:disable cyclomatic_complexity
	// swiftlint:disable:next function_body_length
	static func parseResponse(_ jsonObj: JSON) -> ServerResponse? {
		guard let msg = try? jsonObj.getString(at: "msg") else {
			Log.warn("failed to parse 'msg' from server response", .session)
			return nil
		}
		let queryId = jsonObj.getOptionalInt(at: "queryId") ?? 0
		switch msg {
			//TODO: once appserver updated, need to handle these separately instead of testing on images
			case "results", "execComplete":
				guard let imagesJson = try? jsonObj.getArray(at: "images") else {
					return ServerResponse.results(queryId: queryId, text: jsonObj.getOptionalString(at: "string", or: ""))
				}
				//we override batchId because it is per-session, we need it unique across sessions
				let batchId = max(UserDefaults.standard[.nextBatchId], 1)
				let images = imagesJson.flatMap({ try? SessionImage(json: $0, batchId: batchId) })
				UserDefaults.standard[.nextBatchId] = batchId + 1
				return ServerResponse.execComplete(queryId: queryId, batchId: jsonObj.getOptionalInt(at: "imageBatchId", or: -1), images: images)
			case "showOutput":
				guard let sfile: AppFile = try? jsonObj.decode(at: "file") else {
					Log.warn("failed to decode file parameter to showOutput response", .session)
					return nil
				}
				return ServerResponse.showOutput(queryId: queryId, updatedFile: sfile)
			case "error":
				return ServerResponse.error(queryId: queryId, error: jsonObj.getOptionalString(at: "error", or: "unknown error"))
			case "echo":
				guard let fileId = try? jsonObj.getInt(at: "fileId"), let query = try? jsonObj.getString(at: "query") else
				{
					Log.warn("failed to parse echo response", .session)
					return nil
				}
				return ServerResponse.echoQuery(queryId: queryId, fileId: fileId, query: query)
			case "filechanged":
				guard let ftype = try? jsonObj.getString(at: "type"), let fileId = try? jsonObj.getInt(at: "fileId") else
				{
					Log.warn("failed to parse filechanged response", .session)
					return nil
				}
				let file: AppFile? = try? jsonObj.decode(at: "file")
				return ServerResponse.fileChanged(changeType: ftype, fileId: fileId, file: file)
			case "variables":
				return parseVariables(jsonObj: jsonObj)
			case "saveResponse":
				//TODO: not looking at "success" and handling "error"
				return ServerResponse.saveResponse(transId: jsonObj.getOptionalString(at: "transId", or: ""))
			case "userid":
				return nil //TODO: need to implement
			case "fileOpResponse":
				return parseFileOpResponse(jsonObj: jsonObj)
			default:
				Log.warn("unknown message from server:\(msg)", .session)
				return nil
		}
	}
	
	static func parseFileOpResponse(jsonObj: JSON) -> ServerResponse? {
		guard let transId = try? jsonObj.getString(at: "transId"),
			let opName = try? jsonObj.getString(at: "operation"),
			let op = FileOperation(rawValue: opName),
			let success = try? jsonObj.getBool(at: "success") else
		{
			return nil
		}
		var result: Result<AppFile?, Rc2Error>?
		if success {
			// swiftlint:disable:next force_try (should be impossible since nil is acceptable)
			result = Result<AppFile?, Rc2Error>(value: try! jsonObj.decode(at: "file", alongPath: [.missingKeyBecomesNil, .nullBecomesNil], type: AppFile.self))
		} else {
			result = Result<AppFile?, Rc2Error>(error: parseRemoteError(jsonObj: try? jsonObj.getDictionary(at: "error")))
		}
		return ServerResponse.fileOperationResponse(transId: transId, operation: op, result: result!)
	}
	
	static func parseRemoteError(jsonObj: [String: JSON]?) -> Rc2Error {
		guard let jdict = jsonObj, let code = try? jdict["errorCode"]?.getInt(),
			let errorCode = code,
			let message = try? jdict["errorMessage"]?.getString() ,
			let errorMessage = message else
		{
			Log.warn("server error didn't include code and/or message", .network)
			return Rc2Error(type: .websocket, explanation: "invalid server response")
		}
		let nestedError = WebSocketError(code: errorCode, message: errorMessage)
		return Rc2Error(type: .websocket, nested: nestedError, explanation: errorMessage)
	}
	
	static func parseVariables(jsonObj: JSON) -> ServerResponse? {
		do {
			guard jsonObj.getOptionalBool(at: "delta") else {
				let jsonArray = try jsonObj.getDictionary(at: "variables")
				let vars: [Variable] = try jsonArray.map({ try Variable.variableForJson($0.value) })
				return ServerResponse.variables(single: jsonObj.getOptionalBool(at: "single"), variables: vars)
			}
			let assigned: [Variable] = try jsonObj.getDictionary(at: "variables", "assigned").map({ try Variable.variableForJson($0.value) })
			let removed: [String] = try jsonObj.decodedArray(at: "variables", "removed")
			return ServerResponse.variablesDelta(assigned: assigned, removed: removed)
		} catch {
			Log.error("error parsing variable message: \(error)", .session)
		}
		return nil
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
