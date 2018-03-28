//
//  NetworkingConstants.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Rc2Common
import Foundation
import Model

/// insert, update, delete
public typealias FileChangeType = SessionResponse.FileChangedData.FileChangeType

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
