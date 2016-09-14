//
//  MultipartInputStream.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
fileprivate func < <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l < r
  case (nil, _?):
    return true
  default:
    return false
  }
}


let bodyPartEOL = "\r\n"

private enum ReadState {
	case pre,stream,post,done
}

open class MultipartInputStream: InputStream, StreamDelegate {
	fileprivate var readState:ReadState = .pre
	var streamKeyName:String = "file"
	fileprivate var parts:[String] = []
	var boundary:String = "--Boundary-\(UUID().uuidString)\(bodyPartEOL)"
	fileprivate var preStream:Data?
	fileprivate var stream:InputStream?
	fileprivate var preStreamOffset:Int = 0
	fileprivate var postStreamOffset:Int = 0
	fileprivate var fileName:String!
	fileprivate let postStream:Data

	//following properties of NSStream must be overriden. We just pass to our inner stream
	override open var hasBytesAvailable:Bool {
		if readState == .done { return false }
		return true
	}
	override open var delegate:StreamDelegate? { get { return self } set {} }
	override open var streamStatus:Stream.Status { return stream!.streamStatus }
	override open var streamError:Error? { return stream!.streamError as NSError? }
	
	override init(data: Data) {
		fatalError("data initializer not supported")
	}
			
	override init?(url: URL) {
		self.postStream = "--\(boundary)\(bodyPartEOL)".data(using: String.Encoding.utf8)!
		super.init(url: url)
		self.fileName = url.lastPathComponent
		self.stream  = InputStream(url: url)!
	}
	
	convenience init(URL url: URL, streamKeyName:String) {
		self.init(url:url)!
		self.streamKeyName = streamKeyName
	}
	
	func appendStringPart(_ name:String, value:String) {
		guard preStream == nil else { fatalError("MultipartInputStream is no longer mutable") }
		parts.append("--\(boundary)" + bodyPartEOL +
			"Content-Disposition: form-data; name=\"" + name + "\"" + bodyPartEOL + bodyPartEOL +
			value + bodyPartEOL)
	}
	
	func prepareForRead() {
		guard preStream == nil else { fatalError("MultipartInputStream already prepared") }
		var str:String = parts.reduce("") { $0 + $1 }
		str.append("--\(boundary)\(bodyPartEOL)")
		str.append("Content-Disposition: form-data; name=\"\(streamKeyName)\"; filename=\"\(fileName)\"\(bodyPartEOL)")
		str.append("Content-Type: application/octet-stream\(bodyPartEOL)\(bodyPartEOL)")
		preStream = str.data(using: String.Encoding.utf8)
	}
	
	//pass on to wrapped stream
	override open func open() {
		stream!.open()
	}
	
	//pass on to wrapped stream
	override open func close() {
		stream!.close()
	}
	
	//pass on to wrapped stream
	override open func schedule(in aRunLoop: RunLoop, forMode mode: RunLoopMode) {
		stream!.schedule(in: aRunLoop, forMode: mode)
	}
	
	//pass on to wrapped stream
	override open func property(forKey key: Stream.PropertyKey) -> Any? {
		return stream?.property(forKey: key)
	}
	
	//pass on to wrapped stream
	override open func setProperty(_ property: Any?, forKey key: Stream.PropertyKey) -> Bool {
		return stream!.setProperty(property, forKey: key)
	}

	//the reason we exist
	override open func read(_ buffer: UnsafeMutablePointer<UInt8>, maxLength len: Int) -> Int
	{
		guard stream != nil else { fatalError("no stream specified") }
		guard preStream != nil else { fatalError("failed to call prepareForRead()") }
		var bytesRead = 0
		switch(readState) {
			case .pre:
				if preStreamOffset < preStream?.count {
					bytesRead = bytesFromData(buffer, len: len, data: preStream!, offset: &preStreamOffset)
					preStreamOffset += bytesRead
					if preStreamOffset >= preStream!.count {
						readState = .stream
					}
				} else {
					stream!.open()
					readState = .stream
					fallthrough
				}
			case .stream:
				bytesRead = stream!.read(buffer, maxLength: len)
				if bytesRead == -1 || stream!.streamStatus == .atEnd {
					stream!.close()
					readState = .post
					fallthrough
				}
			case .post:
				if postStreamOffset < postStream.count {
					return bytesFromData(buffer, len: len, data: postStream, offset: &postStreamOffset)
				} else if postStreamOffset >= postStream.count {
					readState = .done
				}
			case .done:
				bytesRead = 0
		}
		return bytesRead
	}
	
	fileprivate func bytesFromData(_ buffer:UnsafeMutablePointer<UInt8>, len:Int, data:Data, offset:inout Int) -> Int
	{
		let bytesToRead = min(data.count - offset, len)
		let range = NSMakeRange(offset, bytesToRead)
		(preStream as NSData?)?.getBytes(buffer, range: range)
		offset += bytesToRead
		return bytesToRead
	}
}
