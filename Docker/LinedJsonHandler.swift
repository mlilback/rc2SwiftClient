//
//  LinedJsonHandler.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Freddy
import ClientCore
import os

///This class takes a socket that contains the response from a docker api call that returned line-delimeted JSON, such as /images/create, and /events. See [this docker issue](https://github.com/docker/docker/issues/16925)

enum LinedJsonMessage {
	case string(String)
	case completed
	case error(DockerError)
}

typealias LinedJsonCallback = (LinedJsonMessage) -> Void

///Parses the http response from a socket that is returning mulitple json messages separated by newlines
class LinedJsonHandler: HijackedResponseHandler {
	private var jsonCallback: LinedJsonCallback
	
	required init(fileDescriptor: Int32, queue: DispatchQueue, jsonHandler: @escaping LinedJsonCallback) {
		let superHandler: DockerMessageHandler = { msg in
			switch msg {
			case .complete:
				jsonHandler(.completed)
			case .error(let err):
				jsonHandler(.error(err))
			case .headers(let headers):
				guard headers.statusCode == 200 else {
					let err = DockerError.httpError(statusCode: headers.statusCode, description: nil, mimeType: nil)
					jsonHandler(.error(err))
					return
				}
			case .data(let data):
				LinedJsonHandler.parse(jsonData: data, jsonCallback: jsonHandler)
			}
		}
		jsonCallback = jsonHandler
		super.init(fileDescriptor: fileDescriptor, queue: queue, handler: superHandler)
	}
	
	required init(fileDescriptor: Int32, queue: DispatchQueue, handler: @escaping DockerMessageHandler) {
		fatalError("init(fileDescriptor:queue:handler:) has not been implemented")
	}
	
	//use class func since can't call self in closure defined before calling super.init
	class func parse(jsonData: Data, jsonCallback: LinedJsonCallback) {
		let str = String(data: jsonData, encoding: .utf8)!
		//enumerate instead of componentsSeparated because \r\n is coalesced into 1 graphene cluster
		var lines = [String]()
		str.enumerateLines { line, _ in
			lines.append(line)
		}
		print("parseJson with \(jsonData.count) bytes and \(lines.count) lines")
		//trim off empty lines at end (which will be there since chunks end with empty line)
		while lines.last!.trimmingCharacters(in: .whitespacesAndNewlines).characters.count == 0 {
			lines.remove(at: lines.endIndex - 1)
		}
		lines.forEach { jsonCallback(.string($0)) }
	}
}
