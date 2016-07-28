//
//  LocalServerProtocol.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

typealias SimpleServerCallback = (success:Bool, error:NSError?) -> Void

@objc protocol LocalServerProtocol {

	///client must call this first, and not call any other methods until the handler has been called
	/// - parameter handler: the handler called when the server has determined if docker is running
	func isDockerRunning(callback: SimpleServerCallback)
	
	///checks to see if there are updates required for the docker engine
	/// - parameter baseUrl: the base url string to check for updates in
	/// - parameter requiredVersion: the version required to properly interact with the client
	/// - parameter callback: after the check returns if an update is required an an error if one ocurred
	func checkForUpdates(baseUrl:String, requiredVersion:Int, callback:SimpleServerCallback)
}
