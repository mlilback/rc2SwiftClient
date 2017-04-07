//
//  LinedJsonHandler.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Freddy
import ClientCore
import os

///This class takes a socket that contains the response from a docker api call that returned line-delimeted JSON, such as /images/create, and /events. See [this docker issue](https://github.com/docker/docker/issues/16925).

enum LinedJsonError: Error {
	case invalidInitialContent
}

///Parses the http response from a socket that is returning mulitple json messages separated by newlines
class LinedJsonHandler: DockerResponseHandler {
	/// Parses the input string into individual lines of json, sending them via handler. Returns any remaining text that didn't have a newline at the end
	///
	/// - Parameter data: the data from the socket
	/// - Returns: any remaining data that didn't end with a newline
	/// - Throws: json parse errors
	override func parse(data: Data) throws -> (MessageType?, Data?) {
		guard data.count >= 2 else { return (nil, data) }
		let ignoreLastLine = data.last! != UInt8(ascii: "\n")
		let str = String(data: data, encoding: .utf8)!
		//enumerate instead of componentsSeparated because \r\n is coalesced into 1 graphene cluster
		var lines = [String]()
		str.enumerateLines { line, _ in
			lines.append(line)
		}
		var remainingData: Data?
		if ignoreLastLine {
			remainingData = lines.last!.data(using: .utf8)
			lines.remove(at: lines.endIndex - 1)
		}
		let jsonArray = try lines.map { try JSON(jsonString: $0) }
		return (.json(jsonArray), remainingData)
	}
}
