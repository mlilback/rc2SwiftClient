//
//  NetworkingError.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import ClientCore

public enum NetworkingError: Error, Rc2DomainError {
	case unsupportedFileType
	case connectionError(Error)
	case canceled
	case uploadFailed(Error)
	case invalidHttpStatusCode(HTTPURLResponse)
}
