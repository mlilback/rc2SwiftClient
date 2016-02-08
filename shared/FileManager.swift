//
//  FileManager.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import BrightFutures

let FileAttrVersion = "io.rc2.FileAttr.Version"
let FileAttrChecksum = "io.rc2.FileAttr.SHA256"

public enum FileError: Int, ErrorType {
	case FileNotFound = 0
	case FailedToSaveFile
}

///Protocol for functions of NSFileManager that we use so we can inject a mock version in unit tests
@objc protocol FileManager {
	func URLForDirectory(directory: NSSearchPathDirectory, inDomain domain: NSSearchPathDomainMask, appropriateForURL url: NSURL?, create shouldCreate: Bool) throws -> NSURL
	func moveItemAtURL(srcURL: NSURL, toURL dstURL: NSURL) throws
	func copyItemAtURL(srcURL: NSURL, toURL dstURL: NSURL) throws
	func removeItemAtURL(URL: NSURL) throws
	func createDirectoryAtURL(url: NSURL, withIntermediateDirectories createIntermediates: Bool, attributes: [String : AnyObject]?) throws
}

extension NSFileManager: FileManager {}

extension FileManager {
	///copies url to a new location in a temporary directory that can be passed to the user or another application
	// (i.e. it is not in our sandbox/app support/cache directories)
	func copyURLToTemporaryLocation(url:NSURL) throws -> NSURL {
		let tmpDir = NSURL(fileURLWithPath:NSTemporaryDirectory()).URLByAppendingPathComponent("Rc2", isDirectory: true)
		_ = try? createDirectoryAtURL(tmpDir, withIntermediateDirectories: true, attributes: nil)
		let destUrl = NSURL(fileURLWithPath: url.lastPathComponent!, relativeToURL: tmpDir)
		_ = try? removeItemAtURL(destUrl)
		try copyItemAtURL(url, toURL: destUrl)
		return destUrl
	}
	
	///Moves the tmpFile downloaded via NSURLSession (or elsewher) to toUrl, setting the appropriate
	/// metadata including xattributes for validating cached File objects
	func moveTempFile(tmpFile: NSURL, toUrl:NSURL, file:File?, inout promise:Promise<NSURL?,FileError>) {
		do {
			if toUrl.checkResourceIsReachableAndReturnError(nil) {
				try removeItemAtURL(toUrl)
			}
			try moveItemAtURL(tmpFile, toURL: toUrl)
			//if a File, set mod/creation date, ignoring any errors
			if let fileRef = file {
				_ = try? toUrl.setResourceValue(fileRef.lastModified, forKey: NSURLContentModificationDateKey)
				_ = try? toUrl.setResourceValue(fileRef.dateCreated, forKey: NSURLCreationDateKey)
				fileRef.writeXAttributes(toUrl)
			}
			promise.success(toUrl)
		} catch let err as NSError {
			log.warning("got error downloading file \(tmpFile.lastPathComponent): \(err)")
			promise.failure(FileError.FailedToSaveFile)
		}
	}
}

extension File {
	///checks to see if file at url is the file we represent
	func urlXAttributesMatch(url:NSURL) -> Bool {
		if let versionData = dataForXAttributeNamed(FileAttrVersion, atURL: url).data,
			let readString = String(data:versionData, encoding:NSUTF8StringEncoding),
			let readVersion = Int32(readString),
			let shaString = NSData(contentsOfURL: url)?.sha256(),
			let readShaData = dataForXAttributeNamed(FileAttrChecksum, atURL: url).data,
			let readShaString = String(data:readShaData, encoding:NSUTF8StringEncoding)
		{
			return readVersion == version && shaString == readShaString
		}
		return false
	}
	
	///writes data to xattributes to later validate if a url points to a file reprsented this object
	func writeXAttributes(toUrl:NSURL) {
		let versionData = String(version).dataUsingEncoding(NSUTF8StringEncoding)
		setXAttributeWithName(FileAttrVersion, data: versionData!, atURL: toUrl)
		if let fileData = NSData(contentsOfURL: toUrl), let shaData = fileData.sha256() {
			setXAttributeWithName(FileAttrChecksum, data: shaData, atURL: toUrl)
		} else {
			log.error("failed to create sha256 checksum for \(toUrl.path)")
		}
	}
}
