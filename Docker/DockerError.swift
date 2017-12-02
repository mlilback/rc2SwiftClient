//
//  DockerError.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

private let myBundle = Bundle(for: DockerAPIImplementation.self)

/// Possible errors from Docker-related types
///
/// - invalidArgument:   invalid data in argument
/// - networkError:      error from a Cocoa network call
/// - cocoaError:        a non-network Cocoa error
/// - httpError:         error returned from a remote server (4xx or 5xx)
/// - alreadyInProgress: the requested operation is already in progress
/// - invalidJson:       the json that was passed in or received over the network is invalid
/// - alreadyExists:     the object to be created already exists
/// - noSuchObject:      the requested/specified object does not exist
/// - conflict:          a conflict (container can't be removed, name already assigned, etc.)
/// - execFailed:        exec command returned non zero value
/// - internalError:     an internal error with a description
/// - unsupportedEvent:  a docker event that is not supported by this framework
public enum DockerError: LocalizedError {
	case dockerNotInstalled
	case dockerNotRunning
	case unsupportedDockerVersion
	case invalidArgument(String?)
	case networkError(NSError?)
	case cocoaError(NSError?)
	case httpError(statusCode: Int, description: String?, mimeType: String?)
	case alreadyInProgress
	case invalidJson(Error?)
	case alreadyExists
	case noSuchObject
	case conflict
	case execFailed
	case internalError(String)
	case unsupportedEvent

	public var errorDescription: String? { return localizedDescription }
	
	public var localizedDescription: String {
		switch self {
			case .dockerNotInstalled: return NSLocalizedString("DockerError_DockerNotInstalled", bundle: myBundle, comment: "")
			case .dockerNotRunning: return NSLocalizedString("DockerError_DockerNotRunning", bundle: myBundle, comment: "")
			case .unsupportedDockerVersion: return NSLocalizedString("DockerError_UnsupportedVersion", bundle: myBundle, comment: "")
			case .httpError(let statusCode, let desc, _):
				guard let desc = desc else { return "http error \(statusCode)" }
				return "\(statusCode) (\(desc))"
			default: return ""
		}
	}

	/// Convience method to create an httpError
	///
	/// - parameter from: the response object
	/// - parameter body: the data returned with the response (usually contains error details)
	///
	/// - returns: a .httpError with the correct associated values
	public static func generateHttpError(from: HTTPURLResponse, body: Data?) -> DockerError {
		var bodyText: String?
		if let data = body, let bodyString = String(data: data, encoding: .utf8) {
			bodyText = bodyString
		}
		return .httpError(statusCode: from.statusCode, description: bodyText, mimeType: from.allHeaderFields["Content-Type"] as? String)
	}
}

extension DockerError: Equatable {
	// swiftlint:disable:next cyclomatic_complexity //how else do we implement this?
	public static func == (lhs: DockerError, rhs: DockerError) -> Bool {
		switch (lhs, rhs) {
			case (.invalidArgument(let a), .invalidArgument(let b)) where a == b: return true
			case (.networkError(let a), .networkError(let b)) where a == b: return true
			case (.cocoaError(let a), .cocoaError(let b)) where a == b: return true
			case (.httpError(let code1, let desc1, let mime1), .httpError(let code2, let desc2, let mime2))
				where code1 == code2 && desc1 == desc2 && mime1 == mime2: return true
			case (.alreadyInProgress, .alreadyInProgress): return true
			case (.invalidJson, .invalidJson): return true
			case (.alreadyExists, .alreadyExists): return true
			case (.noSuchObject, .noSuchObject): return true
			case (.conflict, .conflict): return true
			case (.execFailed, .execFailed): return true
			case (.dockerNotInstalled, .dockerNotInstalled): return true
			case (.unsupportedDockerVersion, .unsupportedDockerVersion): return true
			case (.internalError(let str1), .internalError(let str2)):
				return str1 == str2
			case (.unsupportedEvent, .unsupportedEvent): return true
			default: return false
		}
	}
}
