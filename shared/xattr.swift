//
//  xattr.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//
// based on https://github.com/okla/swift-xattr.git

import Foundation

/** Description of current errno value */
func errnoDescription() -> String {
	return String(validatingUTF8: strerror(errno))!
}


/** Convience wrapper using URL instead of path */
@discardableResult func setXAttributeWithName(_ name: String, data: Data, atURL url: URL) -> String? {
	guard url.isFileURL else { return "invalid file URL" }
	return setxattr(url.path, name, (data as NSData).bytes, data.count, 0, 0) == -1 ? errnoDescription() : nil
}

/** Convience wrapper using URL instead of path */
func dataForXAttributeNamed(_ name: String, atURL url: URL) -> (error: String?, data: Data?) {
	guard url.isFileURL else { return ("invalid file URL", nil) }
	return dataForXAttributeNamed(name, atPath: url.path)
}

/** Convience wrapper using URL instead of path */
@discardableResult func removeXAttributeNamed(_ name: String, atURL url: URL) -> String? {
	guard url.isFileURL else { return "invalid file URL" }
	return removeXAttributeNamed(name, atPath: url.path)
}


/**
Set extended attribute at path

:param: name Name of extended attribute
:param: data Data associated with extended attribute
:param: atPath Path to file, directory, symlink etc

:returns: error description if failed, otherwise nil
*/
@discardableResult func setXAttributeWithName(_ name: String, data: Data, atPath path: String) -> String? {
	return setxattr(path, name, (data as NSData).bytes, data.count, 0, 0) == -1 ? errnoDescription() : nil
}

/**
Get data for extended attribute at path

:param: name Name of extended attribute
:param: atPath Path to file, directory, symlink etc

:returns: Tuple with error description and attribute data. In case of success first parameter is nil, otherwise second.
*/
func dataForXAttributeNamed(_ name: String, atPath path: String) -> (error: String?, data: Data?) {
	
	let bufLength = getxattr(path, name, nil, 0, 0, 0)
	
	if bufLength == -1 {
		return (errnoDescription(), nil)
	} else {
//		let buf = malloc(bufLength)
		let buf = UnsafeMutableRawPointer.allocate(bytes: bufLength, alignedTo: MemoryLayout<UInt8>.alignment)
		defer {
			buf.deallocate(bytes: bufLength, alignedTo: MemoryLayout<UInt8>.alignment)
		}
		if getxattr(path, name, buf, bufLength, 0, 0) == -1 {
			return (errnoDescription(), nil)
		} else {
			return (nil, Data(bytes: buf, count: bufLength))
		}
	}
}

/**
Get names of extended attributes at path

:param: path Path to file, directory, symlink etc

:returns: Tuple with error description and array of extended attributes names. In case of success first parameter is nil, otherwise second.
*/
func xattributeNamesAtPath(_ path: String) -> (error: String?, names: [String]?) {
	let bufLength = listxattr(path, nil, 0, 0)
	if bufLength == -1 {
		return (errnoDescription(), nil)
	} else {
		let buf = UnsafeMutablePointer<Int8>.allocate(capacity: bufLength)
		defer {
			buf.deinitialize()
			buf.deallocate(capacity: bufLength)
		}
		if listxattr(path, buf, bufLength, 0) == -1 {
			return (errnoDescription(), nil)
		} else {
			if var names = NSString(bytes: buf, length: bufLength,
				encoding: String.Encoding.utf8.rawValue)?.components(separatedBy: "\0")
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
func removeXAttributeNamed(_ name: String, atPath path: String) -> String? {
	return removexattr(path, name, 0) == -1 ? errnoDescription() : nil
}
