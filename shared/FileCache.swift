//
//  FileCache.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

public class FileCache: NSObject {
	var fileManager:FileManager
	
	lazy var fileCacheUrl: NSURL = { () -> NSURL in
		do {
			let cacheDir = try self.fileManager.URLForDirectory(.CachesDirectory, inDomain: .UserDomainMask, appropriateForURL: nil, create: true)
			if !cacheDir.checkResourceIsReachableAndReturnError(nil) {
				try self.fileManager.createDirectoryAtURL(cacheDir, withIntermediateDirectories: true, attributes: nil)
			}
			return cacheDir
		} catch let err {
			log.error("failed to create file cache dir:\(err)")
		}
		fatalError("failed to create file cache")
	}()
	
	override init() {
		fileManager = NSFileManager.defaultManager()
		super.init()
	}
	
	func isFileCached(file:File) -> Bool {
		return cachedFileUrl(file).checkResourceIsReachableAndReturnError(nil)
	}
	
	private func cachedFileUrl(file:File) -> NSURL {
		let fileUrl = NSURL(fileURLWithPath: "\(file.fileId).\(file.fileType.fileExtension)", relativeToURL: fileCacheUrl)
		return fileUrl
	}
}
