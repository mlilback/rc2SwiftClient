//
//  DockerResponseHandler.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Freddy
import ClientCore
import os

enum MessageType: Equatable {
	case headers(HttpHeaders), json([JSON]), data(Data), complete, error(Rc2Error)
	
	static func == (a: MessageType, b: MessageType) -> Bool {
		switch (a, b) {
		case (.error(let e1), .error(let e2)):
			return e1.type == e2.type //FIXME: not correct
		case (.complete, .complete):
			return true
		case (.json(let j1), .json(let j2)):
			return j1 == j2
		case (.data(let d1), .data(let d2)):
			return d1 == d2
		case (.headers(let h1), .headers(let h2)):
			return h1 == h2
		default:
			return false
		}
	}
}

protocol DockerResponseHandler: class {
	var fileDescriptor: Int32 { get }
	var callback: (MessageType) -> Void { get }
	var headers: HttpHeaders? { get set }
	func startHandler()
	func closeHandler()
}

extension DockerResponseHandler {
	func parseHeaders(data: Data) throws -> Data {
		do {
			let (headData, remainingData) = try HttpStringUtils.splitResponseData(data)
			guard let headString = String(data: headData, encoding: .utf8),
				let parsedHeaders = try? HttpStringUtils.extractHeaders(headString)
				else
			{
				throw Rc2Error(type: .network, explanation: "failed to parse headers")
			}
			guard parsedHeaders.statusCode >= 200, parsedHeaders.statusCode <= 299 else {
				throw Rc2Error(type: .docker, explanation: "invalid status code")
			}
			headers = parsedHeaders
			return remainingData
		} catch {
			os_log("error parsing data %{public}s", log: .docker, error as NSError)
			throw error
		}
	}
}
