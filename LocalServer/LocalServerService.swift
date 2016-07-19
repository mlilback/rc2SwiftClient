//
//  LocalServerService.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

class LocalServerService : NSObject, NSXPCListenerDelegate {
	func listener(listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
		newConnection.exportedInterface = NSXPCInterface(withProtocol: LocalServerProtocol.self)
		let exportedObject = LocalDockerServer()
		newConnection.exportedObject = exportedObject
		newConnection.resume()
		return true
	}
}
