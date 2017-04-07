//
//  BaseResponseHandler.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Freddy
import ClientCore
import os

///This class takes a socket that contains the response from a docker api call

enum MessageType: Equatable {
	case headers(Data), json([JSON]), data(Data), complete, error
	
	static func == (a: MessageType, b: MessageType) -> Bool {
		switch (a, b) {
		case (.error, .error):
			return true
		case (.complete, .complete):
			return true
		case (.json(let j1), .json(let j2)):
			return j1 == j2
		case (.data(let d1), .data(let d2)):
			return d1 == d2
		case (.headers(let h1), .headers(let h2)):
			return h1 == h2
		default:
			return false
		}
	}
}

///Parses the http response from a socket that is returning mulitple json messages separated by newlines
class DockerResponseHandler {
	private let handler: (MessageType) -> Void
	private let fileHandle: FileHandle
	private var readSource: DispatchSourceRead?
	private var gotHeader = false
	private var myQueue = DispatchQueue.global()
	private var leftoverData: Data?
	
	/// Initiailize an instance
	///
	/// - Parameters:
	///   - fileHandle: the source of the data, must have a valid fileDescriptor value
	init(fileHandle: FileHandle, handler: @escaping (MessageType) -> Void) {
		self.fileHandle = fileHandle
		self.handler = handler
	}
	
	///chokepoint for logging/debugging
	func sendMessage(_ msgType: MessageType) {
		myQueue.async {
			self.handler(msgType)
		}
	}
	
	/// starts reading input
	///
	/// - Parameter queue: the queue to receive dispatch callbacks on
	func start(queue: DispatchQueue = .global()) {
		myQueue = queue
		readSource = DispatchSource.makeReadSource(fileDescriptor: fileHandle.fileDescriptor, queue: queue)
		readSource?.setEventHandler(handler: eventHandler)
		readSource?.setCancelHandler(handler: cancelHandler)
		readSource?.resume()
	}
	
	private func cancelHandler() {
		fileHandle.closeFile()
		//if there was an error, don't send complete
		guard readSource != nil else { return }
		sendMessage(.complete)
	}
	
	private func eventHandler() {
		guard let source = readSource else { return }
		let sizeRead = source.data
		//handle end of stream
		if sizeRead == 0 {
			sendMessage(.complete)
			readSource = nil
			source.cancel()
			return
		}
		var data = fileHandle.readData(ofLength: Int(sizeRead))
		do {
			guard gotHeader else {
				parseInitialContent(data)
				return
			}
			if leftoverData != nil {
				leftoverData?.append(data)
				data = leftoverData!
				leftoverData = nil
			}
			let (message, remaining) = try parse(data: data)
			leftoverData = remaining
			if let actualMessage = message {
				sendMessage(actualMessage)
			}
		} catch {
			readSource = nil
			sendMessage(.error)
			source.cancel()
		}
	}
	
	/// Parses the input string into individual lines of json, sending them via handler. Returns any remaining text that didn't have a newline at the end
	///
	/// - Parameter data: the data from the socket
	/// - Returns: any remaining data that didn't end with a newline
	/// - Throws: json parse errors
	func parse(data: Data) throws -> (MessageType?, Data?) {
		fatalError("subclass must implement parse()")
	}
	
	private func parseInitialContent(_ data: Data) {
		do {
			let (headData, contentData) = try HttpStringUtils.splitResponseData(data)
			//TODO: confirm 200 response on http status from headData
			let (message, remainingData) = try parse(data: contentData)
			leftoverData = remainingData
			sendMessage(.headers(headData))
			gotHeader = true
			if let actualMessage = message {
				sendMessage(actualMessage)
			}
		} catch {
			leftoverData = data
		}
	}
}
