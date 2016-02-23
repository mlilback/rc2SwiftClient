//
//  MultipartInputStream.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

let bodyPartEOL = "\r\n"

private enum ReadState {
	case Pre,Stream,Post,Done
}

public class MultipartInputStream: NSInputStream, NSStreamDelegate {
	private var readState:ReadState = .Pre
	var streamKeyName:String = "file"
	private var parts:[String] = []
	var boundary:String = "--Boundary-\(NSUUID().UUIDString)\(bodyPartEOL)"
	private var preStream:NSData?
	private var stream:NSInputStream?
	private var preStreamOffset:Int = 0
	private var postStreamOffset:Int = 0
	private var fileName:String!
	private let postStream:NSData

	//following properties of NSStream must be overriden. We just pass to our inner stream
	override public var hasBytesAvailable:Bool {
		if readState == .Done { return false }
		return true
	}
	override public var delegate:NSStreamDelegate? { get { return self } set {} }
	override public var streamStatus:NSStreamStatus { return stream!.streamStatus }
	override public var streamError:NSError? { return stream!.streamError }
	
	override init(data: NSData) {
		fatalError("data initializer not supported")
	}
			
	override init?(URL url: NSURL) {
		self.postStream = "--\(boundary)\(bodyPartEOL)".dataUsingEncoding(NSUTF8StringEncoding)!
		super.init(URL: url)
		self.fileName = url.lastPathComponent
		self.stream  = NSInputStream(URL: url)!
	}
	
	convenience init(URL url: NSURL, streamKeyName:String) {
		self.init(URL:url)!
		self.streamKeyName = streamKeyName
	}
	
	func appendStringPart(name:String, value:String) {
		guard preStream == nil else { fatalError("MultipartInputStream is no longer mutable") }
		parts.append("--\(boundary)" + bodyPartEOL +
			"Content-Disposition: form-data; name=\"" + name + "\"" + bodyPartEOL + bodyPartEOL +
			value + bodyPartEOL)
	}
	
	func prepareForRead() {
		guard preStream == nil else { fatalError("MultipartInputStream already prepared") }
		var str:String = parts.reduce("") { $0 + $1 }
		str.appendContentsOf("--\(boundary)\(bodyPartEOL)")
		str.appendContentsOf("Content-Disposition: form-data; name=\"\(streamKeyName)\"; filename=\"\(fileName)\"\(bodyPartEOL)")
		str.appendContentsOf("Content-Type: application/octet-stream\(bodyPartEOL)\(bodyPartEOL)")
		preStream = str.dataUsingEncoding(NSUTF8StringEncoding)
	}
	
	//pass on to wrapped stream
	override public func open() {
		stream!.open()
	}
	
	//pass on to wrapped stream
	override public func close() {
		stream!.close()
	}
	
	//pass on to wrapped stream
	override public func scheduleInRunLoop(aRunLoop: NSRunLoop, forMode mode: String) {
		stream!.scheduleInRunLoop(aRunLoop, forMode: mode)
	}
	
	//pass on to wrapped stream
	override public func propertyForKey(key: String) -> AnyObject? {
		return stream?.propertyForKey(key)
	}
	
	//pass on to wrapped stream
	override public func setProperty(property: AnyObject?, forKey key: String) -> Bool {
		return stream!.setProperty(property, forKey: key)
	}

	//the reason we exist
	override public func read(buffer: UnsafeMutablePointer<UInt8>, maxLength len: Int) -> Int
	{
		guard stream != nil else { fatalError("no stream specified") }
		guard preStream != nil else { fatalError("failed to call prepareForRead()") }
		var bytesRead = 0
		switch(readState) {
			case .Pre:
				if preStreamOffset < preStream?.length {
					bytesRead = bytesFromData(buffer, len: len, data: preStream!, offset: &preStreamOffset)
					preStreamOffset += bytesRead
					if preStreamOffset >= preStream!.length {
						readState = .Stream
					}
				} else {
					stream!.open()
					readState = .Stream
					fallthrough
				}
			case .Stream:
				bytesRead = stream!.read(buffer, maxLength: len)
				if bytesRead == -1 || stream!.streamStatus == .AtEnd {
					stream!.close()
					readState = .Post
					fallthrough
				}
			case .Post:
				if postStreamOffset < postStream.length {
					return bytesFromData(buffer, len: len, data: postStream, offset: &postStreamOffset)
				} else if postStreamOffset >= postStream.length {
					readState = .Done
				}
			case .Done:
				bytesRead = 0
		}
		return bytesRead
	}
	
	private func bytesFromData(buffer:UnsafeMutablePointer<UInt8>, len:Int, data:NSData, inout offset:Int) -> Int
	{
		let bytesToRead = min(data.length - offset, len)
		let range = NSMakeRange(offset, bytesToRead)
		preStream?.getBytes(buffer, range: range)
		offset += bytesToRead
		return bytesToRead
	}
}
