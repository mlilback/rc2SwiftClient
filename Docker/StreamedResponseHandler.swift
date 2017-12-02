//
//  StreamedResponseHandler.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

class StreamedResponseHandler: DockerResponseHandler {
	let maxReadDataSize: Int = 1024 * 1024 * 4 // 4 MB
	let crnl = Data(bytes: [13, 10])
	
	let callback: DockerMessageHandler
	private let readChannel: DispatchIO
	private var dataBuffer = Data()
	private let myQueue: DispatchQueue
	var headers: HttpHeaders?
	private let dataQueue = DispatchQueue(label: "streamed data handler")
	
	/// create a response handler that streams data as it comes in
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
		// TODO: examine why 89 is the error if we canceled the channel
		guard error == 0 || error == 89 else {
			let nserr = NSError(domain: NSPOSIXErrorDomain, code: Int(error), userInfo: nil)
			sendMessage(.error(DockerError.cocoaError(nserr)))
			return
		}
		// dispatchData can be nil if done
		if let dispatchData = data, dispatchData.count > 0 {
			// forward data
			myQueue.sync {
				dispatchData.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) -> Void in
					dataBuffer.append(ptr, count: dispatchData.count)
				}
			}
		} else if done {
			sendMessage(.data(dataBuffer))
			dataBuffer.removeAll()
			sendMessage(.complete)
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
		}
		if dataBuffer.count > 0 {
			sendMessage(.data(dataBuffer))
			dataBuffer.removeAll()
		}
	}
}

