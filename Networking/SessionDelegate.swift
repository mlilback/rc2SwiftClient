//
//  SessionDelegate.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Rc2Common
import Model

public protocol SessionDelegate: class {
	///called when the session is closed. Called when explicity or remotely closed. Not called on application termination
	func sessionClosed()
	///called when a server response is received and not handled internally by the session
	func sessionMessageReceived(_ response: SessionResponse)
	///called when the server has returned an error. Delegate needs to associate it with the cause and error.
	func sessionErrorReceived(_ error: SessionError, details: String?)
	///called when the initial caching/loading of files is complete
	func sessionFilesLoaded(_ session: Session)
	///a script/file had a call to help with the passed in arguments
	func respondToHelp(_ helpTopic: String)
}
