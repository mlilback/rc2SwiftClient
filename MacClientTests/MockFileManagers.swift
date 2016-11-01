//
//  CommonMock.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
@testable import MacClient
import os
import BrightFutures

public class DefaultFileManager: Rc2FileManager {
	public func Url(for directory: FileManager.SearchPathDirectory, domain: FileManager.SearchPathDomainMask, appropriateFor url: URL?, create shouldCreate: Bool) throws -> URL
	{
		return try FileManager.default.url(for: directory, in: domain, appropriateFor: url, create: shouldCreate)
	}
	
	public func move(tempFile: URL, to toUrl: URL, file: File?, promise: inout Promise<URL?, FileError>)
	{
		fatalError("not implemented")
	}
	
	public func moveItem(at srcURL: URL, to dstURL: URL) throws {
		return try FileManager.default.moveItem(at: srcURL, to: dstURL)
	}
	
	public func copyItem(at srcURL: URL, to dstURL: URL) throws {
		return try FileManager.default.copyItem(at: srcURL, to: dstURL)
	}
	
	public func removeItem(at URL: URL) throws {
		try FileManager.default.removeItem(at: URL)
	}
	
	public func createDirectoryHierarchy(at url: URL) throws
	{
		try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
	}
}

class MockFileManager: Rc2DefaultFileManager {
	let tempDirUrl: URL
	
	override init(fileManager: FileManager = FileManager.default) {
		tempDirUrl = URL(fileURLWithPath: NSTemporaryDirectory().appendingFormat("/%@", UUID().uuidString))
		super.init(fileManager: fileManager)
		try! createDirectoryHierarchy(at: tempDirUrl)
	}
	
	deinit {
		if (tempDirUrl as NSURL).checkResourceIsReachableAndReturnError(nil) {
			do {
				try removeItem(at: tempDirUrl)
			} catch _ {
			}
		}
	}
	
	func contentsEqual(atPath path1: String, andPath path2: String) -> Bool {
		os_log("compare files: %{public}s and %{public}s", type:.info, path1, path2)
		do {
			let d1 = try Data(contentsOf: URL(fileURLWithPath: path1))
			let d2 = try Data(contentsOf: URL(fileURLWithPath: path2))
			return d1 == d2
		} catch {
			return false
		}
	}
	
	public override func Url(for directory: FileManager.SearchPathDirectory, domain: FileManager.SearchPathDomainMask, appropriateFor url: URL? = nil, create shouldCreate: Bool = false) throws -> URL
	{
		switch(directory) {
		case .cachesDirectory:
			return tempDirUrl
		default:
			return try super.Url(for: directory, domain: domain, appropriateFor: url, create: shouldCreate)
		}
	}
}
