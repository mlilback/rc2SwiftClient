//
//  WebSocketSource.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import SwiftWebSocket

///wrapper protocol around WebSocket class to allow DI and mocking
public protocol WebSocketSource : class {
	var event: WebSocketEvents { get set }
	var binaryType: WebSocketBinaryType { get set }
	func open(request: URLRequest, subProtocols : [String])
	func close(_ code : Int, reason : String)
	func send(_ message : Any)
}

///declare SwiftWebSocket's WebSocket as conforming to WebSocketSource
extension WebSocket : WebSocketSource {}
