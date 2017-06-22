//
//  TestingWebSocket.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
@testable import Networking
import ClientCore
import Starscream

class TestingWebSocket: WebSocket {
	var stringsWritten = [String]()

	override func connect() {
		// FIXME: xcode 9b2 bitches about missing argument
//		onConnect?()
	}

	override func write(string: String, completion: (() -> ())?) {
		stringsWritten.append(string)
		completion?()
	}

	override func write(data: Data, completion: (() -> ())?) {
		completion?()
	}
	
	/// Fakes a message from the other side of the websocket
	///
	/// - Parameter message: string or data that was "sent"
	func serverSent(_ message: String) {
		callbackQueue.async { [weak self] in
			guard let s = self else { return }
			s.onText?(message)
			s.delegate?.websocketDidReceiveMessage(socket: s, text: message)
		}
	}
}
