//
//  SessionWebSocketWorker.swift
//
//  Copyright ©2018 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import MJLLogger
import Rc2Common
import Starscream
import ReactiveSwift
import Result

fileprivate let pingInterval: Double = 30.0

public class SessionWebSocketWorker {
	/// the status will never revert to uninitialized, connecting, or connected after the first time. Closed and failed are final states.
	public enum SocketStatus: Equatable {
		case uninitialized
		case connecting
		case connected
		case closed
		case failed(Error)

		/// will return true for any two .failed values, regardless of the actual errors
		public static func == (lhs: SessionWebSocketWorker.SocketStatus, rhs: SessionWebSocketWorker.SocketStatus) -> Bool
		{
			switch (lhs, rhs) {
			case (.uninitialized, .uninitialized): return true
			case (.connecting, .connecting): return true
			case (.connected, .connected): return true
			case (.closed, .closed): return true
			case (.failed(_), .failed(_)): return true
			default: return false
			}
		}
	}
	
	public let conInfo: ConnectionInfo
	public let wspaceId: Int
	public let queue: DispatchQueue
	public let status: Property<SocketStatus>
	/// signal that sends a value every time data is received
	public let messageSignal: Signal<Data, NoError>

	private var socket: WebSocket! // use IUO so that it can be created in a func called during init
	private let _status = MutableProperty<SocketStatus>(.uninitialized)
	private let messageObserver: Signal<Data, NoError>.Observer
	
	private var pingRepeater: Repeater?
	
	public init(conInfo: ConnectionInfo, wspaceId: Int, queue: DispatchQueue = .global()) {
		self.conInfo = conInfo
		self.wspaceId = wspaceId
		self.queue = queue
		(messageSignal, messageObserver) = Signal<Data, NoError>.pipe()
		status = Property<SocketStatus>(capturing: _status)
		self.socket = createWebSocket()
		setupWebSocketHandlers()
	}

	public func openConnection() {
		_status.value = .connecting
		socket.connect()
	}
	
	public func close() {
		// SessionStatus ignores the failed associated value when comparing so we use an arbitrary error
		guard  _status.value != .failed(Rc2Error.Rc2ErrorType.network) else { return } //don't close if failed
		assert(_status.value == .connected, "must be connected to close")
		socket.disconnect()
	}
	
	public func send(data: Data) {
		socket.write(data: data)
	}
	
	func webSocketOpened() {
		_status.value = .connected
		pingRepeater = Repeater.every(.seconds(pingInterval)) { [weak self] timer in
			self?.socket.write(ping: Data())
		}
		pingRepeater?.start()
	}
	
	func setupWebSocketHandlers() {
		socket.onConnect = { [unowned self] in
			self.queue.async {
				self.webSocketOpened()
			}
		}
		socket.onDisconnect = { [unowned self] (error) in
			Log.info("got disconnect \(error?.localizedDescription ?? "noerr")", .network)
			if let error = error {
				self._status.value = .failed(error)
			} else {
				self._status.value = .closed
			}
			self.pingRepeater?.pause()
			self.pingRepeater = nil
		}
		socket.onText = { [weak self] message in
			Log.debug("received text", .network)
			guard let data = message.data(using: .utf8) else {
				Log.warn("failed to convert text to data", .network)
				return
			}
			self?.queue.async {
				self?.messageObserver.send(value: data)
			}
		}
		socket.onData = { [weak self] data in
			Log.debug("received data", .network)
			self?.queue.async {
				self?.messageObserver.send(value: data)
			}
		}
	}
	
	func createWebSocket() -> WebSocket {
		#if os(OSX)
		let client = "osx"
		#else
		let client = "ios"
		#endif
		var components = URLComponents()
		components.host = conInfo.host == ServerHost.localHost ? "127.0.0.1" : conInfo.host.host
		components.port = conInfo.host.port
		components.path = "\(conInfo.host.urlPrefix)/ws/\(wspaceId)"
		components.scheme = conInfo.host.secure ? "wss" : "ws"
		components.queryItems = [URLQueryItem(name: "client", value: client),
								 URLQueryItem(name: "build", value: "\(AppInfo.buildNumber)")]
		var request = URLRequest(url: components.url!)
		request.setValue("Bearer \(conInfo.authToken)", forHTTPHeaderField: "Authorization")
		let ws = WebSocket(request: request)
		return ws
	}
}
