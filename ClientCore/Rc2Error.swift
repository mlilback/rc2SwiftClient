//
//  Rc2Error.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

/// A protocol to group domain-specific errors that will be nested inside an Rc2Error
public protocol Rc2DomainError: LocalizedError {}

//error object used throughoout project
public struct Rc2Error: LocalizedError, CustomStringConvertible, CustomDebugStringConvertible {
	/// basic categories of errors
	public enum Rc2ErrorType: String, Error {
		/// a requested object was not found
		case noSuchElement
		/// a requested operation is already in progress
		case alreadyInProgress
		/// problem parsing json, Freddy error is nested
		case invalidJson
		/// an invalid argument was passed (or parsed from json)
		case invalidArgument
		/// nestedError will be the NSError
		case cocoa
		/// nested error is related to the file system
		case file
		/// a wrapped error from a websocket
		case websocket
		/// a generic network error
		case network
		/// an error from the docker engine
		case docker
		/// update of an object failed
		case updateFailed
		/// logical error that is not critical
		case logic
		/// wraps an unknown error
		case unknown
	}

	/// possible severity levels of an error. defaults to .error
	public enum Severity: Int {
		case warning, error, fatal
	}

	/// the generic type of the error
	public let type: Rc2ErrorType
	/// the underlying error that caused the problem
	public let nestedError: Error?
	/// a clue as to how to handle the error
	public let severity: Severity
	/// details about the error suitable to show the user
	public let explanation: String?
	/// location in source code of where error happened
	public let location: String

	public var errorDescription: String? {
		return description
	}

	public var description: String {
		if explanation != nil { return explanation! }
		return "\(type) @ \(location)"
	}
	public var debugDescription: String { return "\(type) @ \(location)" }

	public var nestedDescription: String? { return nestedError?.localizedDescription }

	/// intialize an error
	public init(type: Rc2ErrorType = .unknown, nested: Error? = nil, severity: Severity = .error, explanation: String? = nil, fileName: String = #file, lineNumber: Int = #line)
	{
		self.type = type
		self.nestedError = nested
		self.severity = severity
		self.explanation = explanation
		var shortFile = fileName
		if let lastSlashIdx = fileName.range(of: "/", options: .backwards) {
			shortFile = fileName.substring(from: lastSlashIdx.upperBound)
		}
		self.location = "\(shortFile):\(lineNumber)"
	}
}
