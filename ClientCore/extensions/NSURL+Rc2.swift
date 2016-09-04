//
//  NSURL+Rc2.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

public extension NSURL {
	func localizedName() -> String {
		var appName: String = (self.URLByDeletingPathExtension?.lastPathComponent!)!
		var appNameObj: AnyObject?
		do {
			try getResourceValue(&appNameObj, forKey: NSURLLocalizedNameKey)
			appName = appNameObj as! String
			//remove any extension
			if let dotIndex = appName.characters.indexOf(".") {
				appName = appName.substringToIndex(dotIndex)
			}
			return appName
		} catch _ {} //don't care if it failed
		return lastPathComponent!
	}
	
	/** gets the file size without throwing an error.
	returns: the size of the file. returns 0 if the URL is not a file or on an error
	*/
	func fileSize() -> Int64 {
		guard self.fileURL else { return 0 }
		do {
			var rsrc:AnyObject?
			try getResourceValue(&rsrc, forKey: NSURLFileSizeKey)
			if let size = rsrc as? NSNumber {
				return Int64(size.longLongValue)
			}
		} catch _ {}
		return 0
	}
}

