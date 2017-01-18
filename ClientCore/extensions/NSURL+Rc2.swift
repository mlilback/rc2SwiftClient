//
//  NSURL+Rc2.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

extension URL {
	public func localizedName() -> String {
		var appName: String = (self.deletingPathExtension().lastPathComponent)
		var appNameObj: AnyObject?
		do {
			let bridged = self as NSURL
			try bridged.getResourceValue(&appNameObj, forKey: URLResourceKey.localizedNameKey)
			if let localName = appNameObj as? String {
				appName = localName
			}
			//remove any extension
			if let dotIndex = appName.characters.index(of: ".") {
				appName = appName.substring(to: dotIndex)
			}
			return appName
		} catch _ {} //don't care if it failed
		return lastPathComponent
	}

	///calls checkResourceIsReachable and returns false if an error is thrown
	public func fileExists() -> Bool {
		do {
			return try checkResourceIsReachable()
		} catch {
		}
		return false
	}

	/// calls resourceValues and to check if self is a directory
	///
	/// - Returns: true if this URL represents a directory on the local file system
	public func directoryExists() -> Bool {
		guard isFileURL else { return false }
		if let values = try? resourceValues(forKeys: [.isDirectoryKey]) {
			return values.isDirectory!
		}
		return false
	}

	/// Convience method to load data from a file URL
	///
	/// - returns: contents or nil if Data(contentsOf:) throws an error
	public func contents() -> Data? {
		do {
			return try Data(contentsOf: self)
		} catch {
			return nil
		}
	}
	
	/// gets the file size without throwing an error.
	/// - returns: the size of the file. returns 0 if the URL is not a file or on an error
	public func fileSize() -> Int64 {
		guard self.isFileURL else { return 0 }
		do {
			var rsrc: AnyObject?
			let bridged = self as NSURL
			try bridged.getResourceValue(&rsrc, forKey: URLResourceKey.fileSizeKey)
			if let size = rsrc as? NSNumber {
				return Int64(size.int64Value)
			}
		} catch _ {}
		return 0
	}
}
