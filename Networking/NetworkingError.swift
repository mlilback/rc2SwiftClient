//
//  NetworkingError.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Rc2Common
import Foundation
import Model

public enum NetworkingError: LocalizedError, Rc2DomainError {
	case unauthorized
	case unsupportedFileType
	case timeout
	case connectionError(Error)
	case canceled
	case uploadFailed(Error)
	case invalidHttpStatusCode(HTTPURLResponse)
	case restError(DetailedError)
	
	static func errorFor(response: HTTPURLResponse, data: Data) -> NetworkingError {
		switch response.statusCode {
		case 500:
			guard let error = try? JSONDecoder().decode(DetailedError.self, from: data)
				else { return .invalidHttpStatusCode(response) }
			return .restError(error)
		default:
			return .invalidHttpStatusCode(response)
		}
	}

	public var localizedDescription: String {
		return errorDescription ?? "unknown netorking error"
	}
	
	public var errorDescription: String? {
		switch self {
			case .unauthorized:
				return localizedNetworkString("unauthorized")
			case .unsupportedFileType:
				return localizedNetworkString("unsupportedFileType")
			case .restError(let derror):
				return derror.details
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
