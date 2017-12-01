//
//  SharedConstants.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import os
import MJLLogger

///constants for log categories used by this project
public extension OSLog {
	static let docker: OSLog = OSLog(subsystem: AppInfo.bundleIdentifier, category: "docker")
	static let dockerEvt: OSLog = OSLog(subsystem: AppInfo.bundleIdentifier, category: "docker-evt")
	static let network: OSLog = OSLog(subsystem: AppInfo.bundleIdentifier, category: "network")
	static let model: OSLog = OSLog(subsystem: AppInfo.bundleIdentifier, category: "model")
	static let session: OSLog = OSLog(subsystem: AppInfo.bundleIdentifier, category: "session")
	static let app: OSLog = OSLog(subsystem: AppInfo.bundleIdentifier, category: "app")
	static let core: OSLog = OSLog(subsystem: AppInfo.bundleIdentifier, category: "core")
	static let cache: OSLog = OSLog(subsystem: AppInfo.bundleIdentifier, category: "cache")
}

public extension LogCategory {
	public static let network: LogCategory = LogCategory("network")
	public static let docker: LogCategory = LogCategory("docker")
	public static let dockerEvt: LogCategory = LogCategory("docker-evt")
	public static let model: LogCategory = LogCategory("model")
	public static let session: LogCategory = LogCategory("session")
	public static let core: LogCategory = LogCategory("core")
	public static let app: LogCategory = LogCategory("app")
	public static let cache: LogCategory = LogCategory("cache")
}

public let defaultAppServerPort = 3145
