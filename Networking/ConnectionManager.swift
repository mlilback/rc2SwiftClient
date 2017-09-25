//
//  ConnectionManager.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

/// Manages all connections. Currently only supports the local connection, eventually will also manage remote connections.
public class ConnectionManager {
	/// the actual info for the local docker-managed connection
	private var _localConnection: ConnectionInfo?
	/// connection to the local, docker-managed server. Can only be set once.
	public var localConnection: ConnectionInfo? {
		get { return _localConnection }
		set { precondition(_localConnection == nil); _localConnection = newValue }
	}
	
//	public var defaultLcoalProject: AppProject? { return _localConnection?.project(withName: NetworkConstants.defaultProjectName) }

	public init() {
	}
}
