//
//  LinedJsonHandler.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Freddy
import ClientCore
import os

///This class takes a socket that contains the response from a docker api call that returned line-delimeted JSON, such as /images/create, and /events. See [this docker issue](https://github.com/docker/docker/issues/16925).

enum MessageType: Int {
	case json, complete, error
}

enum LinedJsonError: Error {
	case invalidInitialContent
}

///Parses the http response from a socket that is returning mulitple json messages separated by newlines
class LinedJsonHandler {
	let fileHandle: FileHandle
	let handler: (MessageType, [JSON]) -> Void
	private var readSource: DispatchSourceRead?
	private var gotHeader = false
	private var myQueue = DispatchQueue.global()
	private var leftoverData: Data?
	
	/// Initiailize an instance
	///
	/// - Parameters:
	///   - fileHandle: the source of the data, must have a valid fileDescriptor value
	///   - handler: called each time there is a new json message, or when EOF was reached
	init(fileHandle: FileHandle, handler: @escaping (MessageType, [JSON]) -> Void) {
		self.fileHandle = fileHandle
		self.handler = handler
	}
	
	///chokepoint for logging/debugging
	func sendMessage(_ msgType: MessageType, json: [JSON]) {
		myQueue.async {
			self.handler(msgType, json)
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
		sendMessage(.complete, json: [])
	}
	
	private func eventHandler() {
		guard let source = readSource else { return }
		let sizeRead = source.data
		NSLog("size read = \(sizeRead)")
		//handle end of stream
		if sizeRead == 0 {
			sendMessage(.complete, json: [])
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
			let (json, remaining) = try parse(data: data)
			leftoverData = remaining
			sendMessage(.json, json: json)
		} catch {
			readSource = nil
			sendMessage(.error, json: [])
			source.cancel()
		}
	}
	
	/// Parses the input string into individual lines of json, sending them via handler. Returns any remaining text that didn't have a newline at the end
	///
	/// - Parameter data: the data from the socket
	/// - Returns: any remaining data that didn't end with a newline
	/// - Throws: json parse errors
	private func parse(data: Data) throws -> ([JSON], Data?) {
		guard data.count >= 2 else { return ([], data) }
		let ignoreLastLine = data.last! != UInt8(ascii: "\n")
		let str = String(data: data, encoding: .utf8)!
		//enumerate instead of componentsSeparated because \r\n is coalesced into 1 graphene cluster
		var lines = [String]()
		str.enumerateLines { line, _ in
			lines.append(line)
		}
		var remainingData: Data?
		if ignoreLastLine {
			remainingData = lines.last!.data(using: .utf8)
			lines.remove(at: lines.endIndex - 1)
		}
		let jsonArray = try lines.map { try JSON(jsonString: $0) }
		return (jsonArray, remainingData)
	}
	
	private func parseInitialContent(_ data: Data) {
		do {
			let (_, contentData) = try HttpStringUtils.splitResponseData(data)
			//TODO: confirm 200 response on http status from headData
			let (jsonArray, remainingData) = try parse(data: contentData)
			leftoverData = remainingData
			gotHeader = true
			sendMessage(.json, json: jsonArray)
		} catch {
			leftoverData = data
		}
	}
}
