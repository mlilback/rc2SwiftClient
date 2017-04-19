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
	public init(_ inputStream: InputStream, bufferSize: Int = 10_240) {
		self.init()
		var buffer = [UInt8](repeating: 0, count: bufferSize)
		inputStream.open()
		while inputStream.hasBytesAvailable {
			let readSize = inputStream.read(&buffer, maxLength: bufferSize)
			self.append(&buffer, count: readSize)
		}
		inputStream.close()
	}

	/// Enumerate through slices of contents divided by a particular data value
	///
	/// - Parameters:
	///   - divider: the data to split by
	///   - handler: a closure that is passed a matching slice of data
	public func enumerateComponentsSeparated(by divider: Data, handler: (Data) -> Void) {
		var start = startIndex
		var remainingRange: Range<Data.Index> = start..<endIndex
		while true {
			guard let divRange = range(of: divider, options: [], in: remainingRange) else
			{
				//no more dividers, just handle remaing range
				if !remainingRange.isEmpty {
					handler(subdata(in: remainingRange))
				}
				return
			}
			let matchRange: Range<Data.Index> = start..<divRange.lowerBound
			handler(subdata(in: matchRange))
			start = matchRange.upperBound + divider.count
			remainingRange = start..<endIndex
		}
	}
}
