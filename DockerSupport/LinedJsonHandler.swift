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
	var sentFirstData = false
	/// Parses the input string into individual lines of json, sending them via handler. Returns any remaining text that didn't have a newline at the end
	///
	/// - Parameter data: the data from the socket
	/// - Returns: any remaining data that didn't end with a newline
	/// - Throws: json parse errors
	override func parseChunkData(data: Data) -> MessageType? {
		guard !sentFirstData else { return nil }
		sentFirstData = true
		guard data.count >= 2 else { return .error(Rc2Error(type: .network, explanation: "invalid data from server")) }
		let str = String(data: data, encoding: .utf8)!
		//enumerate instead of componentsSeparated because \r\n is coalesced into 1 graphene cluster
		var lines = [String]()
		str.enumerateLines { line, _ in
			lines.append(line)
		}
		//trim off empty lines at end (which will be there since chunks end with empty line)
		while lines.last!.trimmingCharacters(in: .whitespacesAndNewlines).characters.count == 0 {
			lines.remove(at: lines.endIndex - 1)
		}
		do {
			let jsonArray = try lines.map { try JSON(jsonString: $0) }
			return .json(jsonArray)
		} catch {
			os_log("error parsing json from chunk: %{public}s", log: .docker, error as NSError)
			return .error(Rc2Error(type: .invalidJson, nested: error))
		}
	}
}
