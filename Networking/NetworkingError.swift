//
//  NetworkingError.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import ClientCore
import Foundation
import Freddy

public enum NetworkingError: LocalizedError, Rc2DomainError {
	case unauthorized
	case unsupportedFileType
	case timeout
	case connectionError(Error)
	case canceled
	case uploadFailed(Error)
	case invalidHttpStatusCode(HTTPURLResponse)
	case restError(code: Int, message: String)
	
	static func errorFor(response: HTTPURLResponse, data: Data) -> NetworkingError {
		switch response.statusCode {
		case 500:
			guard let json = try? JSON(data: data),
				let code = try? json.getInt(at: 0, "errorCode"),
				let message = try? json.getString(at: 0, "message") else
			{
				return .invalidHttpStatusCode(response)
			}
			return .restError(code: code, message: message)
		default:
			return .invalidHttpStatusCode(response)
		}
	}

	public var errorDescription: String? {
		switch self {
			case .unauthorized:
				return localizedNetworkString("unauthorized")
			case .unsupportedFileType:
				return localizedNetworkString("unsupportedFileType")
			case .restError(_, let message):
				return message
			case .invalidHttpStatusCode(let rsp):
				return localizedNetworkString("server returned \(rsp.statusCode)")
			default:
				return localizedNetworkString("unknown")
		}
	}
}

public struct WebSocketError: LocalizedError, Rc2DomainError, CustomDebugStringConvertible {
	public enum ErrorType: Int {
		case unknown = 0
		case noSuchFile = 1001
		case fileVersionMismatch = 1002
		case databaseUpdateFailed = 1003
		case computeEngineUnavailable = 1005
		case invalidRequest = 1006
		case computeError = 1007
	}
	
	let code: Int
	let type: ErrorType
	let message: String
	
	init(code: Int, message: String) {
		self.code = code
		self.message = message
		self.type = ErrorType(rawValue: code) ?? .unknown
	}
	
	public var errorDescription: String? { return message }
	
	public var debugDescription: String { return "ws error: \(message) (\(code))" }
}
