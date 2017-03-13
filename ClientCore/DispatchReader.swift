//
//  DispatchReader.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

public protocol DispatchReaderDelegate: class {
	func process(data: Data, reader: DispatchReader)
	func closed(reader: DispatchReader)
}

/// Reads data in chunks from a file descriptor
public class DispatchReader {
	fileprivate let fd: Int32
	fileprivate let source: DispatchSourceRead
	fileprivate weak var delegate: DispatchReaderDelegate?
	fileprivate let fileHandle: FileHandle

	init(_ fd: Int, delegate: DispatchReaderDelegate) {
		self.fd = Int32(fd)
		self.delegate = delegate
		self.source = DispatchSource.makeReadSource(fileDescriptor: self.fd)
		fileHandle = FileHandle(fileDescriptor: self.fd)
		source.setCancelHandler { [unowned self] in
			close(self.fd)
			self.delegate?.closed(reader: self)
		}
		source.setEventHandler { [unowned self] in
			//self.source.d
			let availSize: UInt = self.source.data
			let data = self.fileHandle.readData(ofLength: Int(availSize))
			self.delegate?.process(data: data, reader: self)
		}
		source.activate()
	}

	func cancel() {
		source.cancel()
	}
}
