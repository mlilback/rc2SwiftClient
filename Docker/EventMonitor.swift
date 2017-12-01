//
//  EventMonitor.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Freddy
import MJLLogger

protocol EventMonitorDelegate: class {
	func handleEvent(_ event: Event)
	func eventMonitorClosed(error: DockerError?)
}

protocol EventMonitor: class {
	init(delegate: EventMonitorDelegate) throws
}

final class EventMonitorImpl<ConnectionType: LocalDockerConnection>: EventMonitor
{
	private weak var delegate: EventMonitorDelegate?
	private var connection: ConnectionType!

	required init(delegate: EventMonitorDelegate) throws
	{
		self.delegate = delegate
		let request = URLRequest(url: URL(string: "/events")!)
		self.connection = ConnectionType(request: request, hijack: true, handler: connectionCallback)
		try connection.openConnection()
		connection.writeRequest()
	}

	func connectionCallback(message: LocalDockerMessage) {
		switch message {
		case .headers(let headers):
			guard headers.statusCode == 200 else {
				delegate?.eventMonitorClosed(error: DockerError.httpError(statusCode: headers.statusCode, description: "failed to connect", mimeType: nil))
				return
			}
		case .data(let data):
			handleData(data: data)
		case .complete:
			Log.info("docker event monitor connection ended", .dockerEvt)
			delegate?.eventMonitorClosed(error: nil)
		case .error(let error):
			Log.warn("error from docker event connection: \(error.errorDescription ?? "unknown")", .dockerEvt)
			delegate?.eventMonitorClosed(error: error)
		}
	}
	
	private func handleData(data: Data) {
		do {
			let json = try JSON(data: data)
			guard let parsedEvent = try? Event.parse(json: json), let event = parsedEvent else {
				Log.debug("got invalid event from docker: \(String(data: data, encoding: .utf8)!)", .dockerEvt)
				return
			}
			delegate?.handleEvent(event)
		} catch {
			Log.warn("error parsing docker event: \(error)", .docker)
		}
	}
}
