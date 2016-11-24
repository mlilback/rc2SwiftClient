//
//  DockerError.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import os
import ClientCore

fileprivate let myBundle = Bundle(for: DockerManager.self)

/// Possible errors from Docker-related types
///
/// - networkError:      error from a Cocoa network call
/// - cocoaError:        a non-network Cocoa error
/// - httpError:         error returned from a remote server (4xx or 5xx)
/// - alreadyInProgress: the requested operation is already in progress
/// - invalidJson:       the json that was passed in or received over the network is invalid
/// - alreadyExists:     the object to be created already exists
/// - noSuchObject:      the requested/specified object does not exist
/// - conflict:          a conflict (container can't be removed, name already assigned, etc.)
public enum DockerError: LocalizedError, Rc2DomainError {
	case dockerNotInstalled
	case unsupportedDockerVersion
	case networkError(NSError?)
	case cocoaError(NSError?)
	case httpError(statusCode: Int, description: String?, mimeType: String?)
	case alreadyInProgress
	case invalidJson
	case alreadyExists
	case noSuchObject
	case conflict

	var localizedDescription: String {
		// swiftlint:disable:next cyclomatic_complexity //how else do we implement this?
		switch self {
			case .dockerNotInstalled: return NSLocalizedString("DockerError_DockerNotInstalled", bundle: myBundle, comment: "")
			case .unsupportedDockerVersion: return NSLocalizedString("DockerError_UnsupportedVersion", bundle: myBundle, comment: "")
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
			case (.networkError(let a), .networkError(let b)) where a == b: return true
			case (.cocoaError(let a), .cocoaError(let b)) where a == b: return true
			case (.httpError(let code1, let desc1, let mime1), .httpError(let code2, let desc2, let mime2))
				where code1 == code2 && desc1 == desc2 && mime1 == mime2: return true
			case (.alreadyInProgress, .alreadyInProgress): return true
			case (.invalidJson, .invalidJson): return true
			case (.alreadyExists, .alreadyExists): return true
			case (.noSuchObject, .noSuchObject): return true
			case (.conflict, .conflict): return true
			case (.dockerNotInstalled, .dockerNotInstalled): return true
			case (.unsupportedDockerVersion, .unsupportedDockerVersion): return true
			default: return false
		}
	}
}
