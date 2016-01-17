//
//  WebSocketSource.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Starscream

//wrapper protocol around starscream's WebSocket class to allow DI and mocking
public protocol WebSocketSource : class {
	var delegate : WebSocketDelegate? { get set }
	func connect()
	func disconnect(forceTimeout: Int)
	func writeString(str:String)
	func writeData(data:NSData)
	func writePing(data:NSData)
}

//declare Starscream's WebSocket as conforming to WebSocketSource
extension WebSocket : WebSocketSource {}
