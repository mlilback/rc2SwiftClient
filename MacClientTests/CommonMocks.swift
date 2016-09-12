//
//  CommonMock.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
@testable import MacClient

@objc class DefaultFileManager:NSObject, FileManager {
	func URLForDirectory(_ directory: FileManager.SearchPathDirectory, inDomain domain: FileManager.SearchPathDomainMask, appropriateForURL url: URL?, create shouldCreate: Bool) throws -> URL
	{
		return try FileManager.default.url(for: directory, in: domain, appropriateFor: url, create: shouldCreate)
	}
	
	func moveItemAtURL(_ srcURL: URL, toURL dstURL: URL) throws {
		return try FileManager.default.moveItem(at: srcURL, to: dstURL)
	}
	
	func copyItemAtURL(_ srcURL: URL, toURL dstURL: URL) throws {
		return try FileManager.default.copyItem(at: srcURL, to: dstURL)
	}
	
	func removeItemAtURL(_ URL: Foundation.URL) throws {
		try FileManager.default.removeItem(at: URL)
	}
	
	func createDirectoryAtURL(_ url: URL, withIntermediateDirectories createIntermediates: Bool, attributes: [String : AnyObject]?) throws
	{
		try FileManager.default.createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: attributes)
	}
}

class MockFileManager: FileManager {
	let tempDirUrl: URL
	
	override init() {
		tempDirUrl = URL(fileURLWithPath: NSTemporaryDirectory().appendingFormat("/%@", UUID().uuidString))
		super.init()
		try! createDirectory(at: tempDirUrl, withIntermediateDirectories: true, attributes: nil)

	}
	
	deinit {
		if (tempDirUrl as NSURL).checkResourceIsReachableAndReturnError(nil) {
			do {
				try removeItem(at: tempDirUrl)
			} catch _ {
			}
		}
	}
	
	override func contentsEqual(atPath path1: String, andPath path2: String) -> Bool {
		log.info("compare files: \(path1) and \(path2)")
		return super.contentsEqual(atPath: path1, andPath: path2)
	}
	
	override func url(for directory: FileManager.SearchPathDirectory, in domain: FileManager.SearchPathDomainMask, appropriateFor url: URL?, create shouldCreate: Bool) throws -> URL
	{
		switch(directory) {
			case .cachesDirectory:
				return tempDirUrl
			default:
				return try super.url(for: directory, in: domain, appropriateFor: url, create: shouldCreate)
		}
	}
}
