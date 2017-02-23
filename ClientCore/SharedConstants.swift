//
//  SharedConstants.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import os

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
