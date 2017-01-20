//
//  NetworkingError.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import ClientCore
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
			default:
				return localizedNetworkString("unknown")
		}
	}
}
