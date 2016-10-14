//
//  SharedConstants.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

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

public typealias ProgressHandler = (Progress?) -> Void

public struct AppInfo {
	private static let bundleInfo = Bundle.main.infoDictionary

	public static var bundleIdentifier: String? { return bundleInfo?["CFBundleIdentifier"] as? String }
}
