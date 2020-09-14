//
//  AppError.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Rc2Common

enum AppErrorType: String {
	case saveFailed
	case invalidLogin
	case failedToLoadDocument
	case fileNoLongerExists
}

struct AppError: LocalizedError, Rc2DomainError {
	let type: AppErrorType
	let nestedError: Error?

	init(_ error: AppErrorType, nestedError: Error? = nil) {
		self.type = error
		self.nestedError = nestedError
	}

	/// returns an Rc2Error wrapping this error
	var rc2Error: Rc2Error {
		return Rc2Error(type: .application, nested: self, explanation: userExplanation)
	}

	var errorDescription: String? {
		switch self {
		default:
			return "application error (\(type))"
		}
	}

	// passed to Rc2Error's explanation, will possibly be shown to user
	var userExplanation: String? {
		let errorKey = "\(self.type)ErrorExplanation"
		return NSLocalizedString(errorKey, comment: "Error description")
	}
}
