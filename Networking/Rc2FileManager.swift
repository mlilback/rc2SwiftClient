//
//  Rc2FileManager.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import BrightFutures
import os
import CryptoSwift
import ReactiveSwift

let FileAttrVersion = "io.rc2.FileAttr.Version"
let FileAttrChecksum = "io.rc2.FileAttr.SHA256"

public enum FileError: Error {
	case fileNotFound
	case failedToSaveFile
	case failedToLoadFile
	case readError
	case failedToDownload
	case foundationError(error:NSError)
}

///Protocol for functions of NSFileManager that we use so we can inject a mock version in unit tests
public protocol Rc2FileManager {
	func Url(for directory: Foundation.FileManager.SearchPathDirectory, domain: Foundation.FileManager.SearchPathDomainMask, appropriateFor url: URL?, create shouldCreate: Bool) throws -> URL
	func moveItem(at: URL, to: URL) throws
	func copyItem(at: URL, to: URL) throws
	func removeItem(at: URL) throws
//	func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool, attributes: [String : Any]?) throws
	func createDirectoryHierarchy(at url: URL) throws
	func move(tempFile: URL, to toUrl:URL, file:File?, promise:inout Promise<URL?,FileError>)
	/// synchronously move the file setting xattrs
	func move(tempFile: URL, to toUrl: URL, file: File?) throws
}

public class Rc2DefaultFileManager: Rc2FileManager {
	let fm:FileManager
	
	public init(fileManager: FileManager = FileManager.default) {
		fm = fileManager
	}

	public func moveItem(at: URL, to: URL) throws {
		try fm.moveItem(at: at, to: to)
	}
	
	public func copyItem(at: URL, to: URL) throws {
		try fm.copyItem(at: at, to: to)
	}
	
	public func removeItem(at: URL) throws {
		try fm.removeItem(at: at)
	}
	
	public func createDirectoryHierarchy(at url: URL) throws {
		try Foundation.FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
	}
	
	public func Url(for directory: FileManager.SearchPathDirectory, domain: FileManager.SearchPathDomainMask, appropriateFor url: URL? = nil, create shouldCreate: Bool = false) throws -> URL
	{
		return try fm.url(for: directory, in: domain, appropriateFor: url, create: shouldCreate)
	}
	
	///copies url to a new location in a temporary directory that can be passed to the user or another application
	/// (i.e. it is not in our sandbox/app support/cache directories)
	func copyURLToTemporaryLocation(_ url:URL) throws -> URL {
		let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Rc2", isDirectory: true)
		_ = try createDirectoryHierarchy(at: tmpDir)
		let destUrl = URL(fileURLWithPath: url.lastPathComponent, relativeTo: tmpDir)
		_ = try? removeItem(at: destUrl)
		try copyItem(at: url, to: destUrl)
		return destUrl
	}
	
	///Moves the tmpFile downloaded via NSURLSession (or elsewher) to toUrl, setting the appropriate
	/// metadata including xattributes for validating cached File objects
	public func move(tempFile tmpFile: URL, to toUrl:URL, file:File?, promise:inout Promise<URL?,FileError>) {
		do {
			if try toUrl.checkResourceIsReachable() {
				try removeItem(at: toUrl)
			}
			try moveItem(at:tmpFile, to: toUrl)
			//if a File, set mod/creation date, ignoring any errors
			if let fileRef = file {
				//TODO: fix this to use native URL methods
				_ = try? (toUrl as NSURL).setResourceValue(fileRef.lastModified, forKey: URLResourceKey.contentModificationDateKey)
				_ = try? (toUrl as NSURL).setResourceValue(fileRef.dateCreated, forKey: URLResourceKey.creationDateKey)
				fileRef.writeXAttributes(toUrl)
			}
			promise.success(toUrl)
		} catch let err as NSError {
			os_log("got error downloading file %{public}s: %{public}s", tmpFile.lastPathComponent, err)
			promise.failure(FileError.failedToSaveFile)
		}
	}
	
	///Moves the tmpFile downloaded via NSURLSession (or elsewher) to toUrl, setting the appropriate
	/// metadata including xattributes for validating cached File objects
	public func move(tempFile: URL, to toUrl: URL, file: File?) throws {
		do {
			if let _ = try? toUrl.checkResourceIsReachable() {
				try self.removeItem(at: toUrl)
			}
			try self.moveItem(at:tempFile, to: toUrl)
			//if a File, set mod/creation date, ignoring any errors
			if let fileRef = file {
				//TODO: fix this to use native URL methods
				_ = try? (toUrl as NSURL).setResourceValue(fileRef.lastModified, forKey: URLResourceKey.contentModificationDateKey)
				_ = try? (toUrl as NSURL).setResourceValue(fileRef.dateCreated, forKey: URLResourceKey.creationDateKey)
				fileRef.writeXAttributes(toUrl)
			}
		} catch let err as NSError {
			os_log("got error downloading file %{public}s: %{public}s", tempFile.lastPathComponent, err)
			throw FileError.failedToSaveFile
		}
	}
}

extension File {
	///checks to see if file at url is the file we represent
	func urlXAttributesMatch(_ url:URL) -> Bool {
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
	func writeXAttributes(_ toUrl:URL) {
		let versionData = String(version).data(using: String.Encoding.utf8)
		setXAttributeWithName(FileAttrVersion, data: versionData!, atURL: toUrl)
		if let fileData = try? Data(contentsOf: toUrl)
		{
			let shaData = fileData.sha256()
			setXAttributeWithName(FileAttrChecksum, data: shaData, atURL: toUrl)
		} else {
			os_log("failed to create sha256 checksum for %{public}s", type:.error, toUrl.path)
		}
	}
}
