//
//  NetworkingConstants.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import ClientCore
import Foundation
import os
import Model

/// insert, update, delete
public typealias FileChangeType = SessionResponse.FileChangedData.FileChangeType

//extension OSLog {
//	static let network: OSLog = OSLog(subsystem: Bundle().bundleIdentifier ?? "io.rc2.client", category: "network")
//}

func localizedNetworkString(_ key: String) -> String {
	return NSLocalizedString(key, tableName: "Networking", bundle: Bundle(for: Rc2DefaultFileManager.self), comment: "")
}

public struct NetworkConstants {
	public static let defaultProjectName = "default"
	public static let defaultWorkspaceName = "default"
	public static let defaultBookmarkName = "local"
	public static let localBookmarkGroupName = NSLocalizedString("Local Server", comment: "")
	public static let localServerPassword = "local"
}
