//
//  ServerHost.swift
//  Rc2Client
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Rc2Common

/// Represents a remote host
public struct ServerHost: Codable, CustomStringConvertible, Hashable {
	/// the localhost used when connecting via the embedded docker containers
	public static let localHost: ServerHost = { return ServerHost(name: "Local Server", host: "localhost", port: defaultAppServerPort, user: "local", secure: false) }()
	/// the beta server hosted at api.rc2.io
	public static let betaHost: ServerHost = { return ServerHost(name: "Rc² Beta Cloud", host: "api.rc2.io", port: 443, user: "", urlPrefix: "/dev", secure: true) }()
	/// the production server hosted at api.rc2.io
	public static let cloudHost: ServerHost = { return ServerHost(name: "Rc² Cloud", host: "api.rc2.io", port: 443, user: "", urlPrefix: "", secure: true) }()

	/// user-friendly name for the host. Also used to save to keychain.
	public let name: String
	/// the hostname or IP address to connect to
	public let host: String
	/// the login/username to connect as
	public let user: String
	/// the port the server listens on
	public let port: Int
	/// true if the connection should be made using TLS
	public let secure: Bool
	/// the initial prefix used to access the api on the server. For example, beta uses "/dev" to prefix all URLs.
	public let urlPrefix: String
	
	/// the string used to store the password for this host in the keychain
	public var keychainKey: String {
		if self == ServerHost.localHost { return "\(self.user)@\(self.host)" }
		return "\(self.host)/\(self.urlPrefix):\(self.user)@\(self.host)"
	}
	
	/// Creates a ServerHost
	///
	/// - Parameters:
	///   - name: the user-friendly name for this host
	///   - host: the hostname/ip address
	///   - port: the port the host listens on. Defaults to the port used for the local docker server
	///   - user: the userid/login to use
	///   - urlPrefix: prefix for all URLs on this host. Defaults to empty string.
	///   - secure: true if connection should be made using TLS. Defaults to false (for local server)
	public init(name: String, host: String, port: Int = defaultAppServerPort, user: String, urlPrefix: String = "", secure: Bool = false) {
		self.name = name.lowercased()
		self.host = host
		self.user = user
		self.port = port
		self.urlPrefix = urlPrefix
		self.secure = secure
	}
	
	/// a URL for this server
	public var url: URL? {
		var components = URLComponents()
		components.host = host
		components.port = port
		components.scheme = secure ? "https" : "http"
		components.path = urlPrefix
		return components.url
	}
	
	// documentation inherited from protocol
	public var description: String {
		return "ServerHost \(name) \(user )@(\(host):\(port) \(secure ? "secure" : ""))"
	}
}
