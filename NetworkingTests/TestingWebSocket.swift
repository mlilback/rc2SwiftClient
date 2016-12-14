//
//  TestingWebSocket.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
@testable import Networking
import ClientCore
@testable import SwiftWebSocket

class TestingWebSocket: WebSocketSource {
	var event: WebSocketEvents = WebSocketEvents()
	var binaryType: WebSocketBinaryType = .nsData

	var stringsWritten = [String]()

	func open(request: URLRequest, subProtocols : [String]) {
		event.open()
	}
	
	func close(_ code : Int, reason : String) {
		event.close(0, "mock", true)
	}
	
	func send(_ message : Any) {
		if let str = message as? String {
			stringsWritten.append(str)
		} else {
			NSLog("TestingWebSocket: binary message ignored")
		}
	}
	
	/// Fakes a message from the other side of the websocket
	///
	/// - Parameter message: string or data that was "sent"
	func serverSent(_ message: Any) {
		DispatchQueue.global().async {
			self.event.message(message)
		}
	}
}
