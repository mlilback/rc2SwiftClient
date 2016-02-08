//
//  xattr.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//
// based on https://github.com/okla/swift-xattr.git

import Foundation

/** Description of current errno value */
func errnoDescription() -> String {
	return String(UTF8String: strerror(errno))!
}

/**
Set extended attribute at path

:param: name Name of extended attribute
:param: data Data associated with extended attribute
:param: atPath Path to file, directory, symlink etc

:returns: error description if failed, otherwise nil
*/
func setXAttributeWithName(name: String, data: NSData, atPath path: String) -> String? {
	return setxattr(path, name, data.bytes, data.length, 0, 0) == -1 ? errnoDescription() : nil
}

/**
Get data for extended attribute at path

:param: name Name of extended attribute
:param: atPath Path to file, directory, symlink etc

:returns: Tuple with error description and attribute data. In case of success first parameter is nil, otherwise second.
*/
func dataForXAttributeNamed(name: String, atPath path: String) -> (error: String?, data: NSData?) {
	
	let bufLength = getxattr(path, name, nil, 0, 0, 0)
	
	if bufLength == -1 {
		return (errnoDescription(), nil)
	} else {
//		let buf = malloc(bufLength)
		let buf = UnsafeMutablePointer<Void>.alloc(bufLength)
		defer {
			buf.destroy()
			buf.dealloc(bufLength)
		}
		if getxattr(path, name, buf, bufLength, 0, 0) == -1 {
			return (errnoDescription(), nil)
		} else {
			return (nil, NSData(bytes: buf, length: bufLength))
		}
	}
}

/**
Get names of extended attributes at path

:param: path Path to file, directory, symlink etc

:returns: Tuple with error description and array of extended attributes names. In case of success first parameter is nil, otherwise second.
*/
func xattributeNamesAtPath(path: String) -> (error: String?, names: [String]?) {
	let bufLength = listxattr(path, nil, 0, 0)
	if bufLength == -1 {
		return (errnoDescription(), nil)
	} else {
		let buf = UnsafeMutablePointer<Int8>.alloc(bufLength)
		defer {
			buf.destroy()
			buf.dealloc(bufLength)
		}
		if listxattr(path, buf, bufLength, 0) == -1 {
			return (errnoDescription(), nil)
		} else {
			if var names = NSString(bytes: buf, length: bufLength,
				encoding: NSUTF8StringEncoding)?.componentsSeparatedByString("\0")
			{
				names.removeLast()
				return (nil, names)
			} else {
				return ("Unknown error", nil)
			}
		}
	}
}

/**
Remove extended attribute at path

:param: name Name of extended attribute
:param: atPath Path to file, directory, symlink etc

:returns: error description if failed, otherwise nil
*/
func removeXAttributeNamed(name: String, atPath path: String) -> String? {
	return removexattr(path, name, 0) == -1 ? errnoDescription() : nil
}
