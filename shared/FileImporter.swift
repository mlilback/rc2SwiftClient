//
//  FileImporter.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

/** represents a file to import along with the name to use for it (in case there already is a file with that name. If the name is nil, use the existing file name. */
struct FileToImport {
	var fileUrl: NSURL
	var uniqueFileName: String?
	init(url:NSURL, uniqueName:String?) {
		self.fileUrl = url
		self.uniqueFileName = uniqueName
	}
}

class FileImporter: NSObject, NSProgressReporting {
	var progress:NSProgress
	private var files:[FileToImport]
	
	init(files:[FileToImport]) {
		self.files = files
		let totalFileSize:Int64 = files.map({ $0.fileUrl }).reduce(0) { (size, url) -> Int64 in
			return size + url.fileSize()
		}
		progress = NSProgress(totalUnitCount: totalFileSize)
		super.init()
	}
	
	/** starts the import. To know when complete, observe progress.fractionComplete and is complete when >= 1.0  */
	func startImport() {
		
	}
}
