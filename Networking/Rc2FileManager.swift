//
//  Rc2FileManager.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import ClientCore
import Foundation
import os
import ReactiveSwift

let FileAttrVersion = "io.rc2.FileAttr.Version"
let FileAttrChecksum = "io.rc2.FileAttr.SHA256"

public enum FileError: Error, Rc2DomainError {
	case failedToSave
	case failedToDownload
}

///Protocol for functions of NSFileManager that we use so we can inject a mock version in unit tests
public protocol Rc2FileManager {
	func Url(for directory: Foundation.FileManager.SearchPathDirectory, domain: Foundation.FileManager.SearchPathDomainMask, appropriateFor url: URL?, create shouldCreate: Bool) throws -> URL
	func moveItem(at: URL, to: URL) throws
	func copyItem(at: URL, to: URL) throws
	func removeItem(at: URL) throws
//	func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool, attributes: [String : Any]?) throws
	func createDirectoryHierarchy(at url: URL) throws
	/// synchronously move the file setting xattrs
	func move(tempFile: URL, to toUrl: URL, file: AppFile?) throws
}

open class Rc2DefaultFileManager: Rc2FileManager {
	let fm: FileManager
	
	public init(fileManager: FileManager = FileManager.default) {
		fm = fileManager
	}

	public func moveItem(at: URL, to: URL) throws {
		do {
			try fm.moveItem(at: at, to: to)
		} catch {
			throw Rc2Error(type: .file, nested: error)
		}
	}
	
	public func copyItem(at: URL, to: URL) throws {
		do {
			try fm.copyItem(at: at, to: to)
		} catch {
			throw Rc2Error(type: .file, nested: error, severity: .error, explanation: "failed to copy \(to.lastPathComponent)")
		}
	}
	
	public func removeItem(at: URL) throws {
		do {
			try fm.removeItem(at: at)
		} catch {
			throw Rc2Error(type: .file, nested: error)
		}
	}
	
	public func createDirectoryHierarchy(at url: URL) throws {
		do {
			try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
		} catch {
			throw Rc2Error(type: .file, nested: error)
		}
	}
	
	public func Url(for directory: FileManager.SearchPathDirectory, domain: FileManager.SearchPathDomainMask, appropriateFor url: URL? = nil, create shouldCreate: Bool = false) throws -> URL
	{
		do {
			return try fm.url(for: directory, in: domain, appropriateFor: url, create: shouldCreate)
		} catch {
			throw Rc2Error(type: .file, nested: error)
		}
	}
	
	///copies url to a new location in a temporary directory that can be passed to the user or another application
	/// (i.e. it is not in our sandbox/app support/cache directories)
	public func copyURLToTemporaryLocation(_ url: URL) throws -> URL {
		//all errors are already wrapped since we only call internal methods
		let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Rc2", isDirectory: true)
		_ = try createDirectoryHierarchy(at: tmpDir)
		let destUrl = URL(fileURLWithPath: url.lastPathComponent, relativeTo: tmpDir)
		_ = try? removeItem(at: destUrl)
		try copyItem(at: url, to: destUrl)
		return destUrl
	}
	
	///Synchronously moves the tmpFile downloaded via NSURLSession (or elsewhere) to toUrl, setting the appropriate
	/// metadata including xattributes for validating cached File objects
	public func move(tempFile: URL, to toUrl: URL, file: AppFile?) throws {
		do {
			if let _ = try? toUrl.checkResourceIsReachable() {
				try self.removeItem(at: toUrl)
			}
			try self.moveItem(at:tempFile, to: toUrl)
			//if a File, set mod/creation date, ignoring any errors
			if let fileRef = file {
				var fileUrl = toUrl
				var resourceValues = URLResourceValues()
				resourceValues.creationDate = fileRef.dateCreated
				resourceValues.contentModificationDate = fileRef.lastModified
				try fileUrl.setResourceValues(resourceValues)
				let attrs: [FileAttributeKey: Any] = [.posixPermissions: fileRef.fileType.isExecutable ? 0o775 : 0o664]
				try fm.setAttributes(attrs, ofItemAtPath: fileUrl.path)
				fileRef.writeXAttributes(fileUrl)
			}
		} catch {
			os_log("got error downloading file %{public}@: %{public}@", log: .network, tempFile.lastPathComponent, error.localizedDescription)
			throw Rc2Error(type: .cocoa, nested: error, explanation: tempFile.lastPathComponent)
		}
	}
}

extension AppFile {
	///checks to see if file at url is the file we represent
	public func urlXAttributesMatch(_ url: URL) -> Bool {
		if let versionData = dataForXAttributeNamed(FileAttrVersion, atURL: url).data,
			let readString = String(data:versionData, encoding:String.Encoding.utf8),
			let readVersion = Int(readString),
			let shaData = dataForXAttributeNamed (FileAttrChecksum, atURL: url).data,
			let readShaData = dataForXAttributeNamed(FileAttrChecksum, atURL: url).data
		{
			return readVersion == version && shaData == readShaData
		}
		return false
	}
	
	///writes data to xattributes to later validate if a url points to a file reprsented this object
	public func writeXAttributes(_ toUrl: URL) {
		let versionData = String(version).data(using: String.Encoding.utf8)
		setXAttributeWithName(FileAttrVersion, data: versionData!, atURL: toUrl)
		if let fileData = try? Data(contentsOf: toUrl)
		{
			let shaData = (fileData as NSData).sha1hash()
			setXAttributeWithName(FileAttrChecksum, data: shaData, atURL: toUrl)
		} else {
			os_log("failed to create sha256 checksum for %{public}@", log: .network, type:.error, toUrl.path)
		}
	}
}
