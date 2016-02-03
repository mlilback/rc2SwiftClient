//
//  CommonMock.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
@testable import MacClient

@objc class DefaultFileManger:NSObject, FileManager {
	func URLForDirectory(directory: NSSearchPathDirectory, inDomain domain: NSSearchPathDomainMask, appropriateForURL url: NSURL?, create shouldCreate: Bool) throws -> NSURL
	{
		return try NSFileManager.defaultManager().URLForDirectory(directory, inDomain: domain, appropriateForURL: url, create: shouldCreate)
	}
	
	func moveItemAtURL(srcURL: NSURL, toURL dstURL: NSURL) throws {
		return try NSFileManager.defaultManager().moveItemAtURL(srcURL, toURL: dstURL)
	}
	
	func removeItemAtURL(URL: NSURL) throws {
		try NSFileManager.defaultManager().removeItemAtURL(URL)
	}
	
	func createDirectoryAtURL(url: NSURL, withIntermediateDirectories createIntermediates: Bool, attributes: [String : AnyObject]?) throws
	{
		try NSFileManager.defaultManager().createDirectoryAtURL(url, withIntermediateDirectories: createIntermediates, attributes: attributes)
	}
}
