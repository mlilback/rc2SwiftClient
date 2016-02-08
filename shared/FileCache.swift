//
//  FileCache.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

public class FileCache: NSObject {
	var fileManager:FileManager
	
	override init() {
		fileManager = NSFileManager.defaultManager()
		super.init()
	}
	
	var fileCacheUrl: NSURL {
		do {
			let cacheDir = try fileManager.URLForDirectory(.CachesDirectory, inDomain: .UserDomainMask, appropriateForURL: nil, create: true)
			if !cacheDir.checkResourceIsReachableAndReturnError(nil) {
				try fileManager.createDirectoryAtURL(cacheDir, withIntermediateDirectories: true, attributes: nil)
			}
			return cacheDir
		} catch let err {
			log.error("failed to create file cache dir:\(err)")
		}
		fatalError("failed to create file cache")
	}
	

}
