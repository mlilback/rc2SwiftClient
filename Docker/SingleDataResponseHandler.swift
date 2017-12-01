//
//  SingleDataResponseHandler.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import MJLLogger

class SingleDataResponseHandler: DockerResponseHandler {
	let maxReadDataSize: Int = 1024 * 1024 * 4 // 4 MB
	let crnl = Data(bytes: [13, 10])

	let callback: DockerMessageHandler
	private let readChannel: DispatchIO
	private var dataBuffer = Data()
	private let myQueue: DispatchQueue
	var headers: HttpHeaders?
	private var isRawStream = false
	private let dataQueue = DispatchQueue(label: "singledata handler")
	
	/// create a response handler that reads all data from a dispatch channel
	///
	/// - Parameters:
	///   - channel: the channel to read from
	///   - queue: the queue to perform reads on
	///   - handler: a message handler to call with details on progress
	required init(channel: DispatchIO, queue: DispatchQueue, handler: @escaping DockerMessageHandler)
	{
		self.readChannel = channel
		callback = handler
		myQueue = queue
	}
	
	///chokepoint for logging/debugging
	func sendMessage(_ msgType: LocalDockerMessage) {
//		if case .data(let data) = msgType, data.count == 0 {
//			print("oops")
//		}
		self.callback(msgType)
	}
	
	/// starts reading
	///
	/// - Parameter queue: the queue to receive dispatch callbacks on
	func startHandler() {
		readChannel.setLimit(lowWater: 1)
		readChannel.setLimit(highWater: maxReadDataSize)

		// schedule first read
		readChannel.read(offset: 0, length: maxReadDataSize, queue: dataQueue, ioHandler: readHandler)
	}
	
	func closeHandler() {
		readChannel.close(flags: .stop)
	}
	
	private func readHandler(_ done: Bool, _ data: DispatchData?, _ error: Int32) {
//		guard let channel = readChannel else { return } // must have been closed while waiting on callback
		//schedule a cleanup if done or error
//		if error != 0 || done { defer { closeHandler() } }
		// TODO: examine why 89 is the error if we canceled the channel
		guard error == 0 || error == 89 else {
			let nserr = NSError(domain: NSPOSIXErrorDomain, code: Int(error), userInfo: nil)
			sendMessage(.error(DockerError.cocoaError(nserr)))
			return
		}
		// dispatchData can be nil if done
		if let dispatchData = data, dispatchData.count > 0 {
			// add to buffer
			myQueue.sync {
				dispatchData.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) -> Void in
					dataBuffer.append(ptr, count: dispatchData.count)
				}
			}
		} else if done {
			if isRawStream {
				sendMessage(.data(dataBuffer))
				sendMessage(.complete)
			}
			return
		}
		if nil == headers {
			do {
				dataBuffer = try parseHeaders(data: dataBuffer)
			} catch let error as DockerError {
				sendMessage(.error(error))
				return
			} catch {
				fatalError()
			}
			sendMessage(.headers(headers!))
			isRawStream = headers!.headers["Content-Type"] == "application/vnd.docker.raw-stream"
		}
		guard let headers = headers else { fatalError() }
		guard headers.isChunked else {
			handleNonChunkedData()
			return
		}
		let chunkData = parseSingleChunk()
		guard let cdata = chunkData else {
			return
		}
		sendMessage(.data(cdata))
		sendMessage(.complete)
}

	private func handleNonChunkedData() {
		guard !isRawStream else { return } //we don't do anything with the data
		if let expectedLen = headers?.contentLength, dataBuffer.count < expectedLen
		{
			//don't have all the data. continue reading
			return
		}
		defer {
			sendMessage(.complete)
			readChannel.close()
		}
		guard let headers = headers else { fatalError() }
		guard let dataLen = headers.contentLength, dataBuffer.count >= dataLen else {
			return
		}
		sendMessage(.data(dataBuffer))
	}
	
	func parseSingleChunk() -> Data? {
		guard dataBuffer.count > 0 else { return nil }
		guard let lineEnd = dataBuffer.range(of: crnl) else {
			Log.warn("failed to find CRNL in chunk", .docker)
			return nil
		}
		let sizeData = dataBuffer.subdata(in: 0..<lineEnd.lowerBound)
		guard let dataStr = String(data: sizeData, encoding: .utf8),
			let chunkLength = Int(dataStr, radix: 16)
			else {
				Log.warn("failed to find a chunk header in hijacked data", .docker)
				return nil
		}
		Log.debug("got hijacked chunk length \(chunkLength)", .docker)
		let chunkEnd = chunkLength + sizeData.count + crnl.count
		guard chunkEnd < dataBuffer.count else {
			return nil
		} //if don't have all the chunk data, wait for more data
		let chunkData = dataBuffer.subdata(in: lineEnd.upperBound..<chunkEnd)
		guard chunkData.count > 0 else { return nil }
		return chunkData
	}
//
//	private func parseSingleChunk(data: Data) {
//		guard let lineEnd = data.range(of: crnl) else {
//			os_log("failed to find CRNL in chunk", log: .docker)
//			sendMessage(.error(Rc2Error(type: .docker, nested: DockerError.httpError(statusCode: 500, description: "failed to find CRNL in chunk", mimeType: nil))))
//			return
//		}
//		let sizeData = data.subdata(in: 0..<lineEnd.lowerBound)
//		guard let dataStr = String(data: sizeData, encoding: .utf8),
//			let chunkLength = Int(dataStr, radix: 16)
//			else { fatalError("failed to read chunk length") }
//		os_log("got chunk length %d", log: .docker, type: .debug, chunkLength)
//		guard chunkLength > 0 else {
//			sendMessage(.complete)
//			return
//		}
//		let chunkEnd = chunkLength + sizeData.count + crnl.count
//		let chunkData = data.subdata(in: lineEnd.upperBound..<chunkEnd)
//		sendMessage(.data(chunkData))
//		sendMessage(.complete)
//	}
}
