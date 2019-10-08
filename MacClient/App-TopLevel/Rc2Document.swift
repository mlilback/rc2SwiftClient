//
//  Rc2Document.swift
//
//  Copyright ©2018 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import Model
import Networking

/// Convience method to create an NSError in the Cocoa domain
/// - Parameter code: The cocoa error code
/// - Parameter description: optional description that will be in userInfo
/// - Parameter error: underlying error to place in userInfo
/// - Returns: an error constructed from parameters
func cocoaError(code: Int, description: String?, error: NSError? = nil) -> NSError {
	var info: [String: Any] = [:]
	if let details = description {
		info[NSLocalizedDescriptionKey] = details
	}
	if let error = error {
		info[NSUnderlyingErrorKey] = error
	}
	return NSError(domain: NSCocoaErrorDomain, code: code, userInfo: info)
}

class Rc2Document: NSDocument {
	let myDocumentType = "io.rc2.rc2d"
	private static let encoder = JSONEncoder()
	private static let decoder = JSONDecoder()
	
	var workspace: Workspace!
	var host: ServerHost?
	var session: Session?
	var docData: DocumentData?
	
	override init() {
		super.init()
	}
	
	init(with session: Session) {
		self.session = session
		self.workspace = session.workspace.model
		self.host = session.conInfo.host
		super.init()
	}
	
	override func write(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType, originalContentsURL absoluteOriginalContentsURL: URL?) throws
	{
		guard typeName == myDocumentType else { throw cocoaError(code: NSFileReadUnknownError, description: "unuspported save format") }
		guard let host = host else { fatalError("saving without a host") }
		let fm = FileManager()
		do {
			if !fm.directoryExists(at: url) {
				try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
			}
			let docData = try Rc2Document.encoder.encode(DocumentData(wspace: workspace, host: host))
			try docData.write(to: url.appendingPathComponent("index.json"))
		} catch {
			throw cocoaError(code: NSFileWriteUnknownError, description: "error saving document", error: error as NSError)
		}
	}
}

struct DocumentData: Equatable, Codable {
	let version = 1
	let wspace: Workspace
	let host: ServerHost
}
