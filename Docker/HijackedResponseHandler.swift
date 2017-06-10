//
//  HijackedResponseHandler.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import os

class HijackedResponseHandler: DockerResponseHandler {
	let maxReadDataSize: Int = 1024 * 1024 * 4 // 4 MB
	let crnl = Data(bytes: [13, 10])
	
	let callback: DockerMessageHandler
	private let readChannel: DispatchIO
	private var dataBuffer = Data()
	private let myQueue: DispatchQueue
	var headers: HttpHeaders?
	
	required init(channel: DispatchIO, queue: DispatchQueue, handler: @escaping DockerMessageHandler)
	{
		readChannel = channel
		callback = handler
		myQueue = queue
	}
	
	///chokepoint for logging/debugging
	func sendMessage(_ msgType: LocalDockerMessage) {
		self.callback(msgType)
	}
	
	/// starts reading
	///
	/// - Parameter queue: the queue to receive dispatch callbacks on
	func startHandler() {
		readChannel.setLimit(lowWater: 1)
		readChannel.setLimit(highWater: maxReadDataSize)
		
		// schedule first read
		readChannel.read(offset: 0, length: maxReadDataSize, queue: myQueue, ioHandler: readHandler)
	}
	
	func closeHandler() {
		readChannel.close(flags: .stop)
	}
	
	private func readHandler(_ done: Bool, _ data: DispatchData?, _ error: Int32) {
		//schedule a cleanup if done or error
		if error != 0 || done { defer { closeHandler() } }
		guard error == 0 else {
			let nserr = NSError(domain: NSPOSIXErrorDomain, code: Int(error), userInfo: nil)
			sendMessage(.error(DockerError.cocoaError(nserr)))
			return
		}
		if done && (data == nil || data!.count == 0) { // EOF
			sendMessage(.complete)
			DispatchQueue.global().async { self.closeHandler() }
			return
		}
		guard let dispatchData = data else {
			// should never fail according to documentation
			fatalError("dispatchIO read gave !done with nil data")
		}
		// get data and add to buffer
		dispatchData.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) -> Void in
			dataBuffer.append(ptr, count: dispatchData.count)
		}
		if headers == nil {
			//headers must be included in first read
			do {
				dataBuffer = try parseHeaders(data: dataBuffer)
			} catch let error as DockerError {
				sendMessage(.error(error))
				DispatchQueue.global().async { self.closeHandler() }
				return
			} catch {
				fatalError() //should always be a DockerError
			}
			//make sure returned data is chunked
			guard headers!.isChunked else { fatalError() }
		}
		// we've got headers and possibly data. if the data is a complete chunk, send it as a message
		var exit = false
		while !exit {
			let (complete, chunkData) = parseNextChunk()
			if let cdata = chunkData {
				sendMessage(.data(cdata))
			} else {
				exit = true
			}
			if complete {
				sendMessage(.complete)
			}
		}
		if done {
			sendMessage(.data(dataBuffer))
			sendMessage(.complete)
			return
		}
	}
	
	func parseNextChunk() -> (Bool, Data?) {
		guard dataBuffer.count > 0 else { return (false, nil) }
		guard let lineEnd = dataBuffer.range(of: crnl) else {
			os_log("failed to find CRNL in chunk", log: .docker)
			return (false, nil)
		}
		let sizeData = dataBuffer.subdata(in: 0..<lineEnd.lowerBound)
		guard let dataStr = String(data: sizeData, encoding: .utf8),
			let chunkLength = Int(dataStr, radix: 16)
		else {
			os_log("failed to find a chunk header in hijacked data", log: .docker)
			return (false, nil)
		}
		os_log("got hijacked chunk length %d", log: .docker, type: .debug, chunkLength)
		let chunkEnd = chunkLength + sizeData.count + crnl.count
		guard chunkEnd < dataBuffer.count else {
			return (false, nil)
		} //if don't have all the chunk data, wait for more data
		let chunkData = dataBuffer.subdata(in: lineEnd.upperBound..<chunkEnd)
		dataBuffer.removeSubrange(0..<(chunkEnd + crnl.count))
		guard chunkData.count > 0 else { return (true, nil) }
		return (false, chunkData)
	}
}
