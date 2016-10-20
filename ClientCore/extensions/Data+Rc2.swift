//
//  Data+Rc2.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

public extension Data {
	/// Initializes Data with the contents of inputStream, read synchronously
	///
	/// - parameter inputStream: The stream to read data from
	/// - parameter bufferSize: the size of the buffer to use while reading from inputStream. Defaults to 1 MB
	public init(_ inputStream: InputStream, bufferSize: Int = 10240) {
		self.init()
		var buffer = [UInt8](repeating: 0, count: bufferSize)
		inputStream.open()
		while inputStream.hasBytesAvailable {
			let readSize = inputStream.read(&buffer, maxLength: bufferSize)
			self.append(&buffer, count: readSize)
		}
		inputStream.close()
	}
}
