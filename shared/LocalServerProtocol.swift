//
//  LocalServerProtocol.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

@objc protocol LocalServerProtocol {
	///client must call this first, and not call any other methods until the handler has been called
	/// - parameter handler: the handler called when the server has determined if docker is running
	func isDockerRunning(handler: (Bool) -> Void)
}
