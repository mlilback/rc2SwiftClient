//
//  ChunkedResponseProxy.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import os
import ClientCore

class ChunkedResponseProxy: NSObject, URLSessionDataDelegate {
	private let handler: (String?, Bool) -> Void
	
	init(handler: @escaping (String?, Bool) -> Void) {
		self.handler = handler
		super.init()
	}
	
	deinit {
		print("chunked finished")
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
		guard data.count > 8 else {
			os_log("invalid data from chunked stream", log: .docker)
			dataTask.cancel()
			return
		}
		// parse header
		let (dataLen, isStdErr) = data.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) -> (Int, Bool) in
			let len = data.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) -> Int in
				return ptr.withMemoryRebound(to: Int32.self, capacity: 2) { (intPtr: UnsafePointer<Int32>) -> Int in
					return Int(Int32(bigEndian: intPtr[1]))
				}
			}
			return (len, ptr[0] == 2)
		}
		let str = String(data: data.subdata(in: 8..<dataLen), encoding: .utf8)!
		handler(str, isStdErr)
	}
	
	public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		os_log("why did our session end?: %{public}@", log: .docker, error as NSError? ?? "unknown")
		handler(nil, false)
	}
}
