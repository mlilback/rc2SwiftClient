//
//  FileManager+Rc2.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

public extension FileManager {

	public func directoryExists(at: URL) -> Bool {
		var isDir: ObjCBool = false
		return  self.fileExists(atPath: at.absoluteURL.path, isDirectory: &isDir) && isDir.boolValue
	}
}
