//
//  RawDataResponseHandler.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

class RawDataResponseHandler: DockerResponseHandler {

	/// - Parameter data: the data from the socket
	/// - Returns: any remaining data that didn't end with a newline
	override func parse(data: Data) throws -> (MessageType?, Data?) {
		return (.data(data), nil)
	}
	
}
