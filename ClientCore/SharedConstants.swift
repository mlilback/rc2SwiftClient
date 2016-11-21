//
//  SharedConstants.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import os

let Rc2ErrorDomain = "Rc2ErrorDomain"

///localizedDescription will be looked up based on the key Rc2ErrorCode.(enum label)
public enum Rc2ErrorCode: Int {
	case serverError = 101
	case impossible = 102
	case dockerError = 103
	case noSuchObject = 104
	case networkError = 105
	case invalidJson = 106
	case alreadyExists = 107
}

//TODO: remove this, as should no longer  be used
public typealias ProgressHandler = (Progress?) -> Void

/// a static reference to the app's bundle
public struct AppInfo {
	/// the info dictionary of the application
	private static let bundleInfo = Bundle.main.infoDictionary
	/// the bundle identifier of the application
	public static var bundleIdentifier: String { return bundleInfo?["CFBundleIdentifier"] as? String ?? "io.rc2.MacClient" }
	public static var buildNumber: String { return bundleInfo?["CFBundleVersion"] as? String ?? "??" }
}

public extension OSLog {
	static let docker: OSLog = OSLog(subsystem: AppInfo.bundleIdentifier, category: "docker")
	static let network: OSLog = OSLog(subsystem: AppInfo.bundleIdentifier, category: "network")
	static let model: OSLog = OSLog(subsystem: AppInfo.bundleIdentifier, category: "model")
	static let session: OSLog = OSLog(subsystem: AppInfo.bundleIdentifier, category: "session")
	static let app: OSLog = OSLog(subsystem: AppInfo.bundleIdentifier, category: "app")
	static let core: OSLog = OSLog(subsystem: AppInfo.bundleIdentifier, category: "core")
}
