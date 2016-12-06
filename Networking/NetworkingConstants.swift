//
//  NetworkingConstants.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import os
import ClientCore

//extension OSLog {
//	static let network: OSLog = OSLog(subsystem: Bundle().bundleIdentifier ?? "io.rc2.client", category: "network")
//}

func localizedNetworkString(_ key: String) -> String {
	return NSLocalizedString(key, tableName: "Networking", bundle: Bundle(for: Rc2DefaultFileManager.self), comment: "")
}
