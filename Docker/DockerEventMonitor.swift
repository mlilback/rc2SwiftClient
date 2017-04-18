//
//  DockerEventMonitor.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Freddy
import os
import ClientCore

enum DockerEventType: String {
	//don't care
	// attach, commit, copy, create, exec_create, exec_detach, exec_start, export, top
	//don't know what they do
	// resize, update
	//case oom: out of memory, followed by a die event
	case deleteImage //fail if they are deleting one of our images
	case destroy //only happens if stopped, otherwise die should be sent first
	case die
	case healthStatus
	case kill //die called first
	case pause
	case rename //should not be done under our nose
	case restart //die and start called first
	case stop
	case start
	case unpause
	case volume
}

struct DockerEvent: CustomStringConvertible {
	let eventType: DockerEventType
	let json: JSON

	// swiftlint:disable:next cyclomatic_complexity //how else do we implement this?
	 init?(_ json: JSON) {
		self.json = json
		guard let action = try? json.getString(at: "Action") else { return nil }
		switch action {
			case "delete":
				eventType = .deleteImage
			case "destroy":
				eventType = .destroy
			case "die":
				eventType = .die
			case "health_status":
				eventType = .healthStatus
			case "kill":
				eventType = .kill
			case "pause":
				eventType = .pause
			case "rename":
				eventType = .rename
			case "restart":
				eventType = .restart
			case "start":
				eventType = .start
			case "stop":
				eventType = .stop
			case "unpause":
				eventType = .unpause
			case "volume":
				eventType = .volume
			default:
				return nil
		}
	}

	var description: String {
		return "\(eventType.rawValue): \(json)"
	}
}

protocol DockerEventMonitorDelegate: class {
	func handleEvent(_ event: DockerEvent)
	func eventMonitorClosed(error: Error?)
}

protocol DockerEventMonitor {
	init(baseUrl: URL, delegate: DockerEventMonitorDelegate, sessionConfig: URLSessionConfiguration)
}

final class DockerEventMonitorImpl: DockerEventMonitor
{
	weak var delegate: DockerEventMonitorDelegate?
	var connection: LocalDockerConnection!

	required init(baseUrl: URL, delegate: DockerEventMonitorDelegate, sessionConfig: URLSessionConfiguration)
	{
		self.delegate = delegate
		let request = URLRequest(url: baseUrl.appendingPathComponent("/events").absoluteURL)
		self.connection = LocalDockerConnectionImpl<HijackedResponseHandler>(request: request, hijack: true, handler: connectionCallback)
		connection.openConnection()
		connection.writeRequest()
	}

	func connectionCallback(message: LocalDockerMessage) {
		switch message {
		case .headers(let headers):
			assert(headers.statusCode == 200)
		case .data(let data):
			handleData(data: data)
		case .complete:
			os_log("docker event monitor connection ended", log: .docker, type: .info)
			delegate?.eventMonitorClosed(error: nil)
		case .error(let error):
			os_log("error from docker event connection: %{public}@", log: .docker, error.debugDescription)
			delegate?.eventMonitorClosed(error: error)
		}
	}
	
	private func handleData(data: Data) {
		do {
			let json = try JSON(data: data)
			guard let event = DockerEvent(json) else {
				os_log("got invalid event from docker: %{public}@", log: .docker, type: .debug, String(data: data, encoding: .utf8)!)
				return
			}
			delegate?.handleEvent(event)
		} catch {
			os_log("error parsing docker event: %{public}@", log: .docker, error.localizedDescription)
		}
	}
}
