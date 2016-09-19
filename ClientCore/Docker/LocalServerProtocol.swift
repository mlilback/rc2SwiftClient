//
//  LocalServerProtocol.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

public typealias SimpleServerCallback = (_ success:Bool, _ error:NSError?) -> Void

@objc public protocol LocalServerProtocol {

	///client must call this first, and not call any other methods until the handler has been called
	/// - parameter handler: the handler called when the server has determined if docker is running
	/// - parameter url: the url for the docker daemon to connect to. Use nil to use the unix socket
	func initializeConnection(_ url:String?, handler: SimpleServerCallback)
	
	///checks to see if there are updates required for the docker engine
	/// - parameter baseUrl: the base url string to check for updates in
	/// - parameter requiredVersion: the version required to properly interact with the client
	/// - parameter handler: after the check returns if an update is required an an error if one ocurred
	func checkForUpdates(_ baseUrl:String, requiredVersion:Int, handler:SimpleServerCallback)
}