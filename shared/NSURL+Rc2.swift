//
//  NSURL+Rc2.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

extension URL {
	func localizedName() -> String {
		var appName: String = (self.deletingPathExtension().lastPathComponent)
		var appNameObj: AnyObject?
		do {
			let bridged = self as NSURL
			try bridged.getResourceValue(&appNameObj, forKey: URLResourceKey.localizedNameKey)
			appName = appNameObj as! String
			//remove any extension
			if let dotIndex = appName.characters.index(of: ".") {
				appName = appName.substring(to: dotIndex)
			}
			return appName
		} catch _ {} //don't care if it failed
		return lastPathComponent
	}
	
	/** gets the file size without throwing an error.
	returns: the size of the file. returns 0 if the URL is not a file or on an error
	*/
	func fileSize() -> Int64 {
		guard self.isFileURL else { return 0 }
		do {
			var rsrc:AnyObject?
			let bridged = self as NSURL
			try bridged.getResourceValue(&rsrc, forKey: URLResourceKey.fileSizeKey)
			if let size = rsrc as? NSNumber {
				return Int64(size.int64Value)
			}
		} catch _ {}
		return 0
	}
}

