//
//  ChunkedResponseProxy.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import MJLLogger

class ChunkedResponseProxy: NSObject, URLSessionDataDelegate {
	private let handler: (String?, Bool) -> Void
	private var remainingData = Data()
	
	init(handler: @escaping (String?, Bool) -> Void) {
		self.handler = handler
		super.init()
	}
	
	deinit {
		print("chunked finished")
	}

	func parse(data inData: Data) {
		let headerSize: Int = 8
		var currentOffset: Int = 0
		// add new data to old data
		remainingData.append(inData)
		repeat {
			guard remainingData.count - currentOffset > headerSize else { return }
			// cast first 8 bytes to array of 2 Int32s. Convert the second to big endian to get size of message
			let (type, size) = remainingData.subdata(in: currentOffset..<currentOffset + headerSize).withUnsafeBytes
			{ (ptr: UnsafePointer<UInt8>) -> (UInt8, Int) in
				return (ptr[0], ptr.withMemoryRebound(to: Int32.self, capacity: 2)
				{ (intPtr: UnsafePointer<Int32>) -> Int in
					return Int(Int32(bigEndian: intPtr[1]))
				})
			}
			// type must be stdout or stderr
			guard type == 1 || type == 2 else {
				// FIXME: need to have way to pass error back to caller. until then, crash
				fatalError("invalid hijacked stream type")
			}
			currentOffset += headerSize
			let nextOffset = currentOffset + size
			// if all the data required is not available, break out of loop
			guard nextOffset < remainingData.count else {
				currentOffset -= headerSize
				break
			}
			// pass the data as a string to handler
			let currentChunk = remainingData.subdata(in: currentOffset..<nextOffset)
			handler(String(data: currentChunk, encoding: .utf8), type == 2)
			// mark that data as used
			currentOffset += size
		} while remainingData.count > currentOffset
		//remove data that was processed, leaving any remaining
		remainingData.removeSubrange(0..<currentOffset)
	}

	public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void)
	{
		guard response.httpResponse!.statusCode == 200 else {
			completionHandler(.cancel)
			return
		}
		completionHandler(.allow)
	}

	public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
//		guard data.count > 8 else {
//			os_log("invalid data from chunked stream", log: .docker)
//			dataTask.cancel()
//			return
//		}
//		// parse header
//		let (dataLen, isStdErr) = data.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) -> (Int, Bool) in
//			let len = data.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) -> Int in
//				return ptr.withMemoryRebound(to: Int32.self, capacity: 2) { (intPtr: UnsafePointer<Int32>) -> Int in
//					return Int(Int32(bigEndian: intPtr[1]))
//				}
//			}
//			return (len, ptr[0] == 2)
//		}
//		let str = String(data: data.subdata(in: 8..<(8 + dataLen)), encoding: .utf8)!
//		handler(str, isStdErr)
		parse(data: data)
	}
	
	public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		Log.warn("why did our session end?: \(error?.localizedDescription ?? "unknown")", .docker)
		handler(nil, false)
	}
}
