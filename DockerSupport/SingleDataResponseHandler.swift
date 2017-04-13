//
//  SingleDataResponseHandler.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import os
import ClientCore

class SingleDataResponseHandler: DockerResponseHandler {
	let maxReadDataSize: Int = 1024 * 1024 * 4 // 4 MB
	let crnl = Data(bytes: [13, 10])

	let callback: DockerMessageHandler
	let fileDescriptor: Int32
	private var readChannel: DispatchIO?
	private var dataBuffer = Data()
	private let myQueue: DispatchQueue
	var headers: HttpHeaders?
	
	required init(fileDescriptor: Int32, queue: DispatchQueue, handler: @escaping DockerMessageHandler)
	{
		self.fileDescriptor = fileDescriptor
		callback = handler
		myQueue = queue
	}
	
	///chokepoint for logging/debugging
	func sendMessage(_ msgType: LocalDockerMessage) {
		if case .data(let data) = msgType, data.count == 0 {
			print("oops")
		}
		self.callback(msgType)
	}
	
	/// starts reading
	///
	/// - Parameter queue: the queue to receive dispatch callbacks on
	func startHandler() {
		let fd = fileDescriptor
		readChannel = DispatchIO(type: .stream, fileDescriptor: fileDescriptor, queue: myQueue) { [weak self] (errCode) in
			guard errCode == 0 else {
				let nserr = NSError(domain: NSPOSIXErrorDomain, code: Int(errCode), userInfo: nil)
				self?.sendMessage(.error(Rc2Error(type: .docker, nested: DockerError.cocoaError(nserr), explanation: "error creating io channel")))
				return
			}
			close(fd)
		}
		readChannel!.setLimit(lowWater: 1)
		readChannel!.setLimit(highWater: maxReadDataSize)

		// schedule first read
		readChannel!.read(offset: 0, length: maxReadDataSize, queue: myQueue, ioHandler: readHandler)
	}
	
	func closeHandler() {
		readChannel?.close(flags: .stop)
		readChannel = nil
	}
	
	private func readHandler(_ done: Bool, _ data: DispatchData?, _ error: Int32) {
//		guard let channel = readChannel else { return } // must have been closed while waiting on callback
		//schedule a cleanup if done or error
//		if error != 0 || done { defer { closeHandler() } }
		guard error == 0 || error == 89 else {
			let nserr = NSError(domain: NSPOSIXErrorDomain, code: Int(error), userInfo: nil)
			sendMessage(.error(Rc2Error(type: .docker, nested: DockerError.cocoaError(nserr), explanation: "error reading io channel")))
			return
		}
		// dispatchData can be nil if done
		if let dispatchData = data {
			// add to buffer
			dispatchData.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) -> Void in
				dataBuffer.append(ptr, count: dispatchData.count)
			}
		} else if done {
			return
		}
		if nil == headers {
			do {
				dataBuffer = try parseHeaders(data: dataBuffer)
			} catch let error as Rc2Error {
				sendMessage(.error(error))
				return
			} catch {
				fatalError()
			}
			sendMessage(.headers(headers!))
		}
		guard let headers = headers else { fatalError() }
		guard headers.isChunked else {
			handleNonChunkedData()
			return
		}
		// data is chunked. we'll just parse a single chunk and return it. ignore if says it is done
		if dataBuffer.count > 0 {
			parseSingleChunk(data: dataBuffer)
			return
		}
		// read next chunk
//		channel.read(offset: 0, length: maxReadDataSize, queue: myQueue, ioHandler: readHandler)
	}

	private func handleNonChunkedData() {
		guard let channel = readChannel else { return } // must have been closed while waiting on callback
		guard let headers = headers else { fatalError() }
		guard let dataLen = headers.contentLength else { fatalError() }
		guard dataBuffer.count >= dataLen else {
//			channel.read(offset: 0, length: dataLen, queue: myQueue, ioHandler: readNonChunkedExtra)
			return
		}
		sendMessage(.data(dataBuffer))
		sendMessage(.complete)
		channel.close()
	}
	
	private func readNonChunkedExtra(_ done: Bool, _ data: DispatchData?, _ error: Int32) {
		precondition(headers?.contentLength ?? 0 > 0)
		guard let channel = readChannel else { return } // must have been closed while waiting on callback
		if let dispatchData = data {
			dispatchData.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) -> Void in
				dataBuffer.append(ptr, count: dispatchData.count)
			}
		}
		if let dataLen = headers?.contentLength, dataBuffer.count < dataLen {
			channel.read(offset: 0, length: dataLen, queue: myQueue, ioHandler: readNonChunkedExtra)
			return
		}
		sendMessage(.data(dataBuffer))
		sendMessage(.complete)
		channel.close()
	}
	
	private func parseSingleChunk(data: Data) {
		guard let lineEnd = data.range(of: crnl) else {
			os_log("failed to find CRNL in chunk", log: .docker)
			sendMessage(.error(Rc2Error(type: .docker, nested: DockerError.httpError(statusCode: 500, description: "failed to find CRNL in chunk", mimeType: nil))))
			return
		}
		let sizeData = data.subdata(in: 0..<lineEnd.lowerBound)
		guard let dataStr = String(data: sizeData, encoding: .utf8),
			let chunkLength = Int(dataStr, radix: 16)
			else { fatalError("failed to read chunk length") }
		os_log("got chunk length %d", log: .docker, type: .debug, chunkLength)
		guard chunkLength > 0 else {
			sendMessage(.complete)
			return
		}
		let chunkEnd = chunkLength + sizeData.count + crnl.count
		let chunkData = data.subdata(in: lineEnd.upperBound..<chunkEnd)
		sendMessage(.data(chunkData))
		sendMessage(.complete)
	}
}
