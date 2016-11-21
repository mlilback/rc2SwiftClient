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

final class DockerEventMonitor: NSObject, URLSessionDataDelegate {
	var delegate: DockerEventMonitorDelegate
	var session: URLSession!

	init(baseUrl: URL, delegate: DockerEventMonitorDelegate, sessionConfig: URLSessionConfiguration = URLSessionConfiguration.default)
	{
		self.delegate = delegate
		super.init()
		sessionConfig.timeoutIntervalForRequest = TimeInterval(60 * 60 * 24) //wait a day
		session = URLSession(configuration: sessionConfig, delegate: self, delegateQueue:nil)
		let url = URL(string: "/events", relativeTo: baseUrl)!
		//due to https://bugs.swift.org/browse/SR-2804 we must use an objc object or else chunked property will not be saved
		let request = NSMutableURLRequest(url: url)
		request.rc2_chunkedResponse = true
		let task = session.dataTask(with: request as URLRequest)
		task.resume()
		print("task resumed")
	}

	open func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void)
	{
		completionHandler(Foundation.URLSession.ResponseDisposition.allow)
	}

	open func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
		let str = String(data: data, encoding:String.Encoding.utf8)!
		let messages = str.components(separatedBy: "\n")
		for aMessage in messages {
			guard aMessage.characters.count > 0 else { continue }
			guard let jsonData = aMessage.data(using: .utf8), let json = try? JSON(data: jsonData) else {
				os_log("failed to parse json: %{public}s", log: .docker, aMessage)
				continue
			}
			if let event = DockerEvent(json) {
				delegate.handleEvent(event)
			}
		}
	}

	open func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		os_log("why did our session end?: %{public}s", log: .docker, error as? NSError ?? "unknown")
		delegate.eventMonitorClosed(error: error)
	}
}
